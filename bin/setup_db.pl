#!/usr/bin/env perl
use Moose;
use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
BEGIN { our $Log_Level = 'info' }
 
role MyApp::Role::Index {
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    
    has_file 'shear_index_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'si',
        required      => 1,
        must_exist    => 1,
        documentation => 'Shear index file',
    );

    has_file 'hotspot_index_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'hi',
        required      => 1,
        must_exist    => 1,
        documentation => 'Hotspot index file',
    );

    has_file 'hotspot_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'h',
        required      => 1,
        must_exist    => 1,
        documentation => 'Hotspot BED file',
    );

    has 'hotspot_file_track_line' => (
        is            => 'rw',
        isa           => 'Str',
        documentation => 'Hold hotspot BED track_info',
    );
    

    method get_shear_index {
        my %hash;

        my $in = IO::Uncompress::AnyUncompress->new( $self->shear_index_file->stringify )
            or die "Cannot open: $AnyUncompressError\n";

        while ( my $row = <$in> ) {
            chomp $row;
            if ( $row =~ /^(left\S+|right\S+)\s+(\d+)\s+(\S+)$/ ) {
                my ( $shear_id, $n_reads, $read_name_string ) = ( $1, $2, $3 );
                my @read_names = split( ',', $read_name_string );
                $hash{$shear_id} = \@read_names;
            }
            else {
                say $row;
                die $self->shear_index_file . " doesn't seem to be an shears index file!";
            }
        }

        close($in);

        return \%hash;
    }

    method get_hotspot_index {
        my %hash;

        my $in = IO::Uncompress::AnyUncompress->new( $self->hotspot_index_file->stringify )
            or die "Cannot open: $AnyUncompressError\n";

        while ( my $row = <$in> ) {
            chomp $row;
            if ( $row =~ /^(hotspot\d+)\s+(\S+)\s+(\d+)\s+(\S+)$/ ) {
                my ( $hotspot_id, $sha256_id, $n_shears, $shear_id_string ) = ( $1, $2, $3, $4 );
                my @shear_ids = split( ',', $shear_id_string );
                $hash{$hotspot_id}{sha256} = $sha256_id;
                $hash{$hotspot_id}{shears} = \@shear_ids;
            }
            else {
                say $row;
                die $self->hotspot_index_file . " doesn't seem to be a hotspot index file!";
            }
        }

        close($in);

        return \%hash;
    }

    method get_read_names_from_hotspots {
        my %reads_ht;
        #my %ht_reads;

        $self->log->info("Indexing shears");
        my $shear_index = $self->get_shear_index;

        $self->log->info("Indexing hotspots");
        my $ht_index = $self->get_hotspot_index;

        my $in = Bio::Moose::BedIO->new(file => $self->hotspot_file->stringify);
        while (my $f = $in->next_feature) {
            my $ht_id = $f->name;
            if ($ht_index->{$ht_id}){
                foreach my $shear_id (@{$ht_index->{$ht_id}->{shears}}) {
                    #push(@{$ht_reads{$ht_id}{$shear_id}}, @{$shear_index->{$shear_id}});

                    foreach my $read (@{$shear_index->{$shear_id}}){
                        $reads_ht{$read} = { shear_id => $shear_id, hotspot_id => $ht_id };
                    }
                }
            }
            $self->hotspot_file_track_line($f->track_line) if $f->track_line;
        }
 
        #return \%ht_reads;
        return \%reads_ht;
    }


    method get_hotspots_shear_reads () {
        my $reads_ht = $self->get_read_names_from_hotspots;
        my %ht;
        foreach my $read (sort {$a cmp $b} keys %{$reads_ht}) {
            my $aux = $reads_ht->{$read};
            $ht{$aux->{hotspot_id}}{$aux->{shear_id}}{$read} = 1;
        }
        return \%ht;
    }
}


class MyApp::Populate is dirty {
    use MooseX::App qw(Color Config);
    use TCSeq::DB::Schema;
    use Log::Any::App '$log',
        -screen => { pattern_style => 'script_long' },
        -file => { path => 'logs/', level => 'debug' };

    has 'log' => (
        is            => 'ro',
        isa           => 'Object',
        required      => 1,
        default       => sub { return $log },
        documentation => 'Keep Log::Any::App object',
    );

    has 'schema' => (
        is            => 'rw',
        isa           => 'Object',
        lazy          => 1,
        builder       => '_build_schema',
        documentation => 'Schema',
    );
    
    option 'sqlite' => (
        is            => 'rw',
        isa           => 'Bool',
        required      => '1',
        default       => 0,
        documentation => q[Use SQLite backend instead of MySQL],
    );
 
    option 'sqlite_file' => (
        is            => 'rw',
        isa           => 'Str',
        required      => '1',
        default       => 'breakpointdb.db',
        documentation => q[SQLite filename used when SQLite backend is chosen],
    );

    option 'dsn' => (
          is            => 'rw',
          isa           => 'Str',
          required      => '1',
          default => 'dbi:mysql:dbname=breakpoints;host=alpha.rockefeller.edu',
          documentation => q[DSN information],
    );

    option 'db_user' => (
          is            => 'rw',
          isa           => 'Str',
          required      => '0',
          documentation => q[Databse Username if using mysql],
    );
    
     option 'db_pass' => (
          is            => 'rw',
          isa           => 'Str',
          required      => '0',
          documentation => q[Databse password if using mysql],
    );
  
    option 'library_name' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(l)],
          required      => '1',
          documentation => q[Library name],
    );
 

    method _build_schema {
        my $schema;

        if ( $self->sqlite && !$self->db_user && !$self->db_pass) {
            $schema = TCSeq::DB::Schema->connect(
                'dbi:SQLite:dbname='.$self->sqlite_file,
                '',
                '',
                '',
                { on_connect_call => ['use_foreign_keys'] },

            );
            $schema->deploy() unless ( -e $self->sqlite_file );

        }
        else {
            $schema = TCSeq::DB::Schema->connect( 
                $self->dsn,
                $self->db_user, 
                $self->db_pass, 
            );
        }

        return $schema;
    }
}

class MyApp::Populate::Library {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;

    command_short_description q[Add target.sorted.shears_index to database];

    option 'library_name' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(l)],
          required      => '1',
          documentation => q[Library name],
    );
    
    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $schema = $self->schema;
        
        my $in = IO::Uncompress::AnyUncompress->new($self->input_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";
        
        while ( my $row = <$in> ){
            chomp $row;
            my ($shear_id,$n_reads,$read_id) = split "\t",$row;
            my $rs_shear = $schema->resultset('Shear');
            my $shear = $rs_shear->create(
                {
                    shear_id    => $shear_id,
                    shear_chr   => 'chr1',
                    shear_start => 0,
                    shear_end   => 1,
                }
            );
        last;   
        }
        
        close( $in );
        

        $self->log->warn("==> END $cmd <==");
    }
}

class MyApp::Populate::ShearIndexMemory {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;

    command_short_description q[Add target.sorted.shears_index to database];

    has_file 'shear_index_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(si)],
        required      => 1,
        default => '/work/tcseq_test_data/target.sorted.shears_index',
        documentation => q[Shear index file],
    );

    has_file 'shear_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(S)],
        required      => 1,
        documentation => q[Shear BED file],
    );


    method _parse_shear_file {
        my $in =
          IO::Uncompress::AnyUncompress->new( $self->shear_file->stringify )
          or die "Cannot open: $AnyUncompressError\n";

        my %hash;
        while ( my $row = <$in> ) {
            chomp $row;
            next unless $row =~ /^chr/;
            my ( $chr, $start, $end, $shear_name, $n_reads, $strand ) =
              split "\t", $row;
            
              $hash{$shear_name} = {
                chr     => $chr,
                start   => $start,
                end     => $end,
                strand  => $strand,
                n_reads => $n_reads
            };
        }

        close($in);

        return \%hash;
    }

    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $schema = $self->schema;

        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->create({
                library_name => $self->library_name,
            });
        
        my $lib_id = $library->id;

        my $in = IO::Uncompress::AnyUncompress->new($self->shear_index_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";

        my @shears;
        my @shears_f = (qw/shear_id shear_name shear_chr shear_start shear_end shear_strand library_id/);
        my @seqs;
        my @seqs_f = (qw/seq_id read_name library_id/);
        my @shear_seq;
        my @shear_seq_f = (qw/seq_id shear_id/);

        my $shear_id = $schema->resultset('Shear')->get_column('shear_id')->max();
        $shear_id = 0 unless $shear_id;


        my $seq_id = $schema->resultset('Seq')->get_column('seq_id')->max();
        $seq_id = 0 unless $seq_id;

        my $shear_info = $self->_parse_shear_file;

        while ( my $row = <$in> ) {
            chomp $row;
            my ( $shear_name, $n_reads, $read_names ) = split "\t", $row;
            # Shears are only stored if they have more than 2 reads
            next if $n_reads < 2;
            my @reads = split ",", $read_names;

            $shear_id++;
            my $info = $shear_info->{$shear_name};

            unless ($info){
                p $row;

                die "cannot find info about shear: $shear_name"
            }
            push @shears, [ $shear_id, $shear_name, $info->{chr}, $info->{start}, $info->{end}, $info->{strand}, $lib_id ];

            # Adding read_id and linking to shear
            foreach my $read_name (@reads) {
                $seq_id++;
                push @seqs, [ $seq_id, $read_name, $lib_id ];
                push @shear_seq, [ $seq_id, $shear_id ];
           }
        }

        close($in);

        $self->log->info("Populating Shears");
        $schema->resultset('Shear')->populate( [ \@shears_f, @shears, ] );

        $self->log->info("Populating reads");
        $schema->resultset('Seq')->populate( [ \@seqs_f, @seqs, ] );

        $self->log->info("Populating Shears has reads");
        $schema->resultset('ShearHasSeq')->populate( [ \@shear_seq_f, @shear_seq ] );


        $self->log->warn("==> END $cmd <==");
    }
}

class MyApp::Populate::HotspotIndexMemory {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;

    command_short_description q[Add hotspots to database];

    has_file 'hotspot_index_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(hi)],
        required      => 1,
        default => '/work/tcseq_test_data/Lib1g_50kb_removed.shears.hotspots_index',
        documentation => q[Hotspot index file],
    );

    has_file 'hotspot_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(H)],
        required      => 1,
        documentation => q[Hotspot BED file],
    );

    method _parse_hotspot_file {
        my $in =
          IO::Uncompress::AnyUncompress->new( $self->hotspot_file->stringify )
          or die "Cannot open: $AnyUncompressError\n";

        my %hash;
        while ( my $row = <$in> ) {
            chomp $row;
            next unless $row =~ /^chr/;
            my ( $chr, $start, $end, $hotspot_dummy_name, $hotspot_size, $n_shears, $n_left, $n_right, $pvalue ) =
              split "\t", $row;
            
              $hash{$hotspot_dummy_name} = {
                chr     => $chr,
                start   => $start,
                end     => $end,
                hotspot_dummy_name  => $hotspot_dummy_name,
                hotspot_size => $hotspot_size,
                n_shears => $n_shears,
                n_left => $n_left,
                n_right => $n_right,
                pvalue => $pvalue

            };
        }

        close($in);

        return \%hash;
    }

    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $schema = $self->schema;

        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->find(
                {library_name => $self->library_name},
            );
        
        my $lib_id = $library->id;

        my $in = IO::Uncompress::AnyUncompress->new($self->hotspot_index_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";

        my $hotspot_info = $self->_parse_hotspot_file;
        


        while ( my $row = <$in> ) {
            chomp $row;
            my ( $hotspot_dummy_name,$hotspot_name, $n_shears, $shear_names ) = split "\t", $row;
            
            my @shears= split ",", $shear_names;

            my $info = $hotspot_info->{$hotspot_dummy_name};

            unless ($info){
                p $row;

                die "cannot find info about hotspot: $hotspot_dummy_name";
            }


            my $ht = $schema->resultset('Hotspot')->create( {
                      hotspot_dummy_name  => $hotspot_dummy_name,
                      hotspot_name  => $hotspot_name,
                      hotspot_chr  => $info->{chr} ,
                      hotspot_start  => $info->{start} ,
                      hotspot_end  => $info->{end} ,
                      hotspot_pvalue  => $info->{pvalue} ,
                      library_id => $lib_id,
                });
            
            my $ht_id = $ht->id;

            # Adding read_id and linking to shear
            foreach my $shear_name (@shears) {
                my $shear = $schema->resultset('Shear')
                  ->find( {shear_name => $shear_name} );
                $schema->resultset('HotspotHasShear')->create(
                    {
                        hotspot_id => $ht_id,
                        shear_id   => $shear->id,
                    }
                );
            }
        }

        close($in);

        $self->log->warn("==> END $cmd <==");
    }
}

class MyApp::Populate::BreakpointIndexMemory {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;

    command_short_description q[Add breakpoint to database];

    has_file 'breakpoint_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(B)],
        required      => 1,
        documentation => q[Hotspot BED file],
    );

    method _parse_breakpoint_file {
        my $in =
          IO::Uncompress::AnyUncompress->new( $self->breakpoint_file->stringify )
          or die "Cannot open: $AnyUncompressError\n";

        my %hash;
        while ( my $row = <$in> ) {
            chomp $row;
            next unless $row =~ /^chr/;
            my ( $chr, $start, $end, $breakpoint_name, $n_reads, $strand ) =
              split "\t", $row;

            my ( $n_reads_used, $n_reads_aligned, $n_shear_reads, $shear_name );

            if ( $breakpoint_name =~ /^[\*|\#]*\((\d+)\/(\d+)\|(\d+)\)_(\S+)$/ ) {
                ( $n_reads_used, $n_reads_aligned, $n_shear_reads, $shear_name )
                  = ( $1, $2, $3, $4 );
            }
            else {
                $self->log->error(
                    "Cannot parse breakpoint name: $breakpoint_name");
                die;
            }

            $hash{$breakpoint_name} = {
                chr             => $chr,
                start           => $start,
                end             => $end,
                strand          => $strand,
                shear_name      => $shear_name,
                n_shear_reads   => $n_shear_reads,
                n_reads_used    => $n_reads_used,
                n_reads_aligned => $n_reads_aligned,
            };
        }

        close($in);

        return \%hash;
    }

    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $schema = $self->schema;

        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->find(
                {library_name => $self->library_name},
            );
      
        my $lib_id = $library->id;

        my $breakpoint_info = $self->_parse_breakpoint_file;

        foreach my $breakpoint_name (sort {$a cmp $b} keys %{$breakpoint_info}) {
            my $info = $breakpoint_info->{$breakpoint_name};
            
            # get shear id
            my  $shear = $schema->resultset('Shear')->find({shear_name => $info->{shear_name}});
           
            my $break = $schema->resultset('Breakpoint')->create(
                {
                    breakpoint_name            => $breakpoint_name,
                    breakpoint_chr             => $info->{'chr'},
                    breakpoint_start           => $info->{'start'},
                    breakpoint_end             => $info->{'end'},
                    breakpoint_strand          => $info->{'strand'},
                    breakpoint_n_reads_used    => $info->{'n_reads_used'},
                    breakpoint_n_reads_aligned => $info->{'n_reads_aligned'},
                    library_id                 => $lib_id,
                }
            );

            # Link breakpoint to shear
            $schema->resultset('ShearHasBreakpoint')->create(
                {
                    breakpoint_id => $break->id,
                    shear_id      => $shear->id,
                }
            );
        }

        $self->log->warn("==> END $cmd <==");
    }
}

class MyApp::Populate::FastaIndexMemory {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::SeqIO;
    use Data::Printer;

    command_short_description q[Add fasta sequence to database];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(i)],
        required      => 0,
        documentation => q[Input file],
    );

    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $schema = $self->schema;

        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->find(
                {library_name => $self->library_name},
            );
        die "Cannot find library_id for:".$self->library_name unless ($library); 

        my $lib_id = $library->id;

        my $table_name;


        if ($self->input_file =~ /targets_filtered\.fasta/){
            $table_name = 'TargetSequence';
        }
        elsif  ($self->input_file =~ /baits_filtered\.fasta/){
            $table_name = 'BaitSequence';
        } 

#        my $reads_rs = $schema->resultset('Seq')->search(
            #{   'me.library_id'      => $lib_id,
                #'hotspot_dummy_name' => [qw /hotspot21  hotspot10 hotspot11/]
            #},
            #{   join => { 'seq_has_shear' => { 'shear' => { 'shear_has_hotspot' => 'hotspot' } } },
                #'+select' => ['hotspot.hotspot_dummy_name','shear.shear_name'],
                #'+as'     => [qw/ hotspot_dummy_name shear_name/],
            #}
        #);

#        say $reads_rs->count;
        #while (my $read = $reads_rs->next ) {
            #say join "\t", ($read->read_name , $read->get_column('hotspot_dummy_name') );
        #}

        my $reads_rs = $schema->resultset('Seq')->search(
            {   'me.library_id'      => $lib_id,
            },
        );

        my %reads_info;
        $self->log->info("Indexing Sequences");
        while (my $read = $reads_rs->next) {
            $reads_info{$read->read_name} = $read->id;
        } 
       
       $self->log->info("Reading fasta");
       my $in = IO::Uncompress::AnyUncompress->new($self->input_file->stringify) 
          or die "Cannot open: $AnyUncompressError\n";
      
       my $bioin = Bio::SeqIO->new( -fh => $in, -format => 'fasta' );
       
       my @sequences_f = (qw/ seq_id sequence /);
       my @sequences;

       
       while (my $seq = $bioin->next_seq){
           push @sequences, [ $reads_info{$seq->id}, $seq->seq ] if $reads_info{$seq->id};
       }
       close( $in );

       $self->log->info('Populating database');
       $schema->resultset($table_name)->populate( [ \@sequences_f, @sequences, ] );
       
    }
}

class MyApp::Populate::SelectHotspots {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    
    method run {
        # Code Here
        my $schema = $self->schema;
        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->find(
                {library_name => $self->library_name},
            );
        die "Cannot find library_id for:".$self->library_name unless ($library); 

        my $lib_id = $library->id;

        my $hotspots_rs = $schema->resultset('Hotspot')->search(
            { 'me.library_id' => $lib_id,
              '-or' =>[
                  'target_sequence.sequence' => { 'like' => '%GGGAGGTG_CTCT%' },
                  'bait_sequence.sequence' => { 'like' => '%GGGAGGTG_CTCT%' },
                ]
            },
            {   prefetch =>
                   [ {'hotspot_has_shears' => { 'shear' => { 'shear_has_seqs' => {'seq' => [ 'target_sequence','bait_sequence'] } } } }],
            }
        );
        
        say $hotspots_rs->count;

        my $total_seq;
        while (my $ht = $hotspots_rs->next ) {
            
            my $shears = $ht->shears;
            say $ht->hotspot_dummy_name." (".$shears->count.")"." [".$ht->hotspot_chr.":".$ht->hotspot_start."-".$ht->hotspot_end."]";
            next;
            while (my $shear = $shears->next){
                my $seqs = $shear->seqs;
                say "\t".$shear->shear_name." (".$seqs->count.")";

                while (my $seq = $seqs->next){
                    say "\t\t".$seq->read_name;
                    my $target = $seq->target_sequence;
                    my $bait = $seq->bait_sequence;
                    say "\t\t\ttarget: ".$target->get_column('sequence');
                    say "\t\t\tbait: ".$bait->get_column('sequence');
                    $total_seq++;
                }
            }
        }
    }
    
}


class Main {
    import MyApp::Populate;
    MyApp::Populate->new_with_command->run();
}

