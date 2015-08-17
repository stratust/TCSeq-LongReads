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
 
    option 'deploy' => (
          is            => 'rw',
          isa           => 'Bool',
          required      => '0',
          documentation => q[Deploy database before populate?],
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

        $schema->deploy({add_drop_table => 1}) if ( $self->deploy );

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
           
            my $break = $schema->resultset('Breakpoint')->find_or_create(
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
            
            my $breakpoint_id = $break->breakpoint_id;
            unless ($breakpoint_id) {
                $break = $schema->resultset('Breakpoint')->find(
                    {
                        breakpoint_name => $breakpoint_name,
                        library_id      => $lib_id
                    }
                );
            }


            # Link breakpoint to shear
            $schema->resultset('ShearHasBreakpoint')->find_or_create(
                {
                    breakpoint_id => $break->breakpoint_id,
                    shear_id      => $shear->shear_id,
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


# Microhomology Analysis
#-----------------------------------------------------------------------------------------------------
class MyApp::Populate::MicrohomolgySelectHotspots {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    use File::Path qw(mkpath);
    
    option 'genome_fasta_file' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(f)],
          required      => '1',
          documentation => q[Genome FASTA file],
    );

    option 'output_dir' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(o)],
          required      => '1',
          documentation => q[Output directory],
    );

    method get_fasta_for_coord(Str $coord) {
        my $cmd = "echo '".$coord."' | fastaFromBed -fi ".$self->genome_fasta_file." -bed - -fo stdout";
        my $fasta = qx/$cmd/;
        chomp $fasta;
        return($fasta);
    }

    method align_sequence (Str $hotspot_id, Str $hotspot_fragment, Str $read_id, Str $bait_sequence) {
        my $bait_fragment =
            ">Myc\nATCACCCTCTATCACTCCACACACTGAGCGGGGGCTCCTAGATAACTCATTCGTTCGTCCTTCCCCCTTTCTAAATTCTGTTTTCCCCAGCCTTAGAGAGACGCCTGGCCGCCCGGGACGTGCGTGACGCGGTCCAGGGTACATGGCGTATTGTGTGGAGCGAGGCAGCTGTTCCACCTGCGGTGACTGATATACGCAGGGCAAGAACACAGTTCAGCCGAGCGCTGCGCCCGAACAACCGTACAGAAAGGGAAAGGACTAGCGCGCGAGCAAGAGAAAATGGTCGGGCGCGCAGTTAATTCATGCTGCGCTATTACTGTTTACACCCCGGAGCCGGAGTACTGGGCTGCGGGGCTGAGGCTCCTCCTCCTCTTTCCCCGGCTCCCCACTAGCCCCCCTCCCGAGTTCCCAAAGCAGAGGGCGGGGAAGCGAGAGGAGGAAAAAAAAATAGAGAGAGGTGGGGAAGGGAGAAAGAGAGATTCTCTGGCTAATCCCCGCCCACCCGCCCTTTATATTCCGGGGGTCTGCGCGGCCGAGGACCCCTGGGCTGCGCTGCTCTCAGCTGCCGGGTCCGACTCGCCTCACTCAGCTCCCCTCCTGCCTCCTGAAGGGCAGGGCTTCGCCGACGCTTGGCGGGAAAAAGAAGGGAGGGGAGGGATCCTGAGTCGCAGTATAAAAGAAGCTTTTCGGGCGTTTTTTTCTGACTCGCTGTAGTAATTCCAGCGAGAGACAGAGGGAGTGAGCGGACGGTTGGAAGAGCCGTGTGTGCAGAGCCGCGCTCCGGGGCGACCTAAGAAGGCAGCTCTGGAGTGAGAGGGGCTTTGCCTCCGAGCCTGCCGCCCACTCTCCCCAACCCTGCGACTGACCCAACATCAGCGGCCGCAACCCTCGCCGCCGCTGGGAAACTTTGCCCATTGCAGCGGGCAGACACTTCTCACTGGAACTTACAATCTGCGAGCCAGGACAGGACTCCCCAGGCTCCGGGGAGGGAATTTTTGTCTATTTGGGGACAGTGTTCTCTGCCTCTGCCCGCGATCAGCTCTCCTGAAAAGAGCTCCTCGAGCTGTTTGAAGGCTGGATTTCCTTTGGGCGTTGGAAACCCCGGTAAGCACAGATCTGGTGGTCTTTCCCTGTGTTCTTTCTGCGTCTTGAATGTAGCGGCCGGTTAGGACAGTCTTTCTTCCATTCCTGTGCTTTTGACACTTTTCTCAAGAGTAGTTGGGGTAGGCTGGGGTAGATCTGAGTCGGGGTAGAGCGACTTGTCAAGATGACAGAGGAAAGGGGAAGGGAAAAACCGGGATGCATTTTGAAGCGGGGTTCCCGAGGTTACTATGGGCTGACGCTGACCCGGCCGGTTGGACATTCTTGCTTTGCTACATTAATTGATATGTGTCCTTTGAGGGGTCAAACCGGGAGGTCGCTTCGTGGTGGCCAAAGAAAGCCCTTGGAATCCTGAGGTCTTTGGAGAAGGGATTACCTTTTGCGTTTGGGAGCGAGAAGGCTCCGTAGCTTCTGACTTACCAGTCTCTGAGAGGGCATTTAAATTTCAGCTTGGTGCATTTCTGACAGCCTGGGACCGACACGGAGGTGCGTCCCGCCCGCCAATCCCCGGCGGCGATCGCAACCCGTCCCTGAGCCTTTTAAGAAGTTGCTATTTTGGCTTTAAAAATAGTGATCGTAGTAAAATTTAAGCCTGACCCCCGCGGCACTAGGACTTGATGTTGGGCTAGCGCAGTGAGGAGAAGCAAAATTGGGACAGGGATGTGACCGATTCGTTGACTTGGGGGAAACCAGAGGGAATCCTCACATTCCTACTTGGGATCCGCGGGTATCCCTCGCGCCCCTGAATTGCTAGGAAGACTGCGGTGAGTCGTGATCTGAGCGGTTCCGTAACAGCTGCTACCCTCGGCGGGGAGAGGGAAGACGCCCTGTAGGGATAACAGGGTAATGGCCGGCCCAAGGGCGAATTCATAACTTCGTATAATGTATGCTATACGAAGTTATAAGCTTTCGCGAGCTCGAATCGGATCCGAATTCTTAATTAACACCCAGTGCTGAATCGCTGCAGGGTCTCTGGTGCAGTGGCGTCGCGGTTTAGAGTGTAGAAGGGAGGTGTCTCTTATTATTTGACACCCCCTCCCCTTTTATTTCGAGAGGCTTGTGATAGCCGGAGACTGAGCTCTCTCCTCCAAGTCAGCAATCGGAAAGAAAAGCCGGCAAAGGAAGGAAGGGGGCGCGCTGGGGGTGGAGAAAGAGGAGGGCGGAGAGGGGCGGCGGCGCCGGCTGGGTAGGAGCGCGGCGACGGCGCGAATAGGGACTCGGACCCGGTCGGCGGCGCAGAGAGCCGGCACACGGGAGGGGGCCGAGCGACGCGGCGCCTCTCGCCTTTCTCCTTCAGGTGGCGCAAAACTTTGCGCCTCGGCTCTTAGCAGACTGTATTCCCTACAGTCGCCTCCCTCAGCCTCTGAAGCCAAGGCCGATGGCGATTCCTGGGCGTCTGCAGGGCTAAGTCCCTGCTCGAAGGAGGCGGGGACTCGGAGCAGCTGCTAGTCCGACGAGCGTCACTGATAGTAGGGAGTAAAAGAGTGCATGCCTCCCCCCCAACCACACACACACACACACACACACACACACACACACACACACACACACTTGGAAGTACAGCACGCTGAAAGGGGAGTGGTTCAGGATTGGGGTACGCGCTGCGCCAGGTTTCCGCACCAACCAGAGCTGGATAACTCTAGACTTGCTTCCCTTGCTGTGCCCCCTCCAGCAGACAGCCACGACGATGCCCCTCAACGTGAACTTCACCAACAGGAACTATGACCTCGACTACGACTCCGTACAGCCCTATTTCATCTGCGACGAGGAAGAGAATTTCTATCACCAGCAACAGCAGAGCGAGCTGCAGCCGCCCGCGCCCAGTGAGGATATCTGGAAGAAATTCGAGCTGCTTCCCACCCCGCCCCTGTCCCCGAGCCGCCGCTCCGGGCTCTGCTCTCCATCCTATGTTGCGGTCGCTACGTCCTTCTCCCCAAGGGAAGACGATGACGGCGGCGGTGGCAACTTCTCCACCGCCGATCAGCTGGAGATGATGACCGAGTTACTTGGAGGAGACATGGTGAACCAGAGCTTCATCTGCGATCCTGACGACGAGACCTTCATCAAGAACATCATCATCCAGGACTGTATGTGGAGCGGTTTCTCAGCCGCTGCCAAGCTGGTCTCGGAGAAGCTGGCCTCCTACCAGGCTGCGCGCAAAGACAGCACCAGCCTGAGCCCCGCCCGCGGGCACAGCGTCTGCTCCACCTCCAGCCTGTACCTGCAGGACCTCACCGCCGCCGCGTCCGAGTGCATTGACCCCTCAGTGGTCTTTCCCTACCCGCTCAACGACAGCAGCTCGCCCAAATCCTGTACCTCGTCCGATTCCACGGCCTTCTCTCCTTCCTCGGACTCGCTGCTGTCCTCCGAGTCCTCCCCACGGGCCAGCCCTGAGCCCCTAGTGCTGCATGAGGAGACACCGCCCACCACCAGCAGCGACTCTGGTAAGCTACCCCATTCACAGCAGGGTAGGAAGCGAGAGGTTGGATGGACCTCCTTCTCCACCACTCATTGGCATTAATTCAATTGGCCTCCGGGGCTCCCCCTTTCTTTCCCTTCTGTCTAAGAGCTCTTCATCCCTGGATTCCCGTGCTTCAGCTATCCCTCCCTCCCCTCCCCCCCCCCCCCCCAGACCGCCCTGGTTGTCACCCCCACCCCCCACCCTT";

        # create directory if doesnt exist;
        my $dir = $self->output_dir."/".$hotspot_id;
        unless (-d $dir) {
            mkpath($dir);
        }

        my $ref = "$dir/reference.fa";
        my $ref_index = "$dir/reference";

        # Create reference fasta file and smalt index
        unless ( -e $ref ){
           open( my $out, '>', $ref )
               || die "Cannot open/write file " . $ref . "!";
           
               say $out $bait_fragment;
               say $out $hotspot_fragment;
           close( $out );
           
           my $cmd="smalt index -k 11 -s 1 $ref_index $ref > $dir/smalt_index.log 2>&1";
           system($cmd);
        }
        
        my $fasta_seq=">$read_id\n$bait_sequence";
        my $fasta_file="$dir/$read_id.fa";
        my $sam_file="$dir/$read_id.sam";
        my $bam_file="$dir/$read_id.bam";
        open( my $read_out, '>', $fasta_file )
            || die "Cannot open/write file " . $fasta_file . "!";
        say $read_out $fasta_seq; 
        close( $read_out );
        
        system("smalt map -f sam -p -c 11 -x -n 1 -O -o $sam_file $ref_index $fasta_file >> $dir/smalt_map.log 2>&1");
        
        if (-e $sam_file){
            system("samtools view -Sb $sam_file > $bam_file");
            if (-e $bam_file){
                unlink $sam_file or warn "Could not unlink $sam_file: $!";
            }
        }
    }

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
            {   'me.library_id' => $lib_id,

                #'-or' => [
                #    'target_sequence.sequence' => { 'like' => '%GGGAGGTG_CTCT%' },
                #    'bait_sequence.sequence'   => { 'like' => '%GGGAGGTG_CTCT%' },
                #]
            },
            {   prefetch => [
                    {   'hotspot_has_shears' => {
                            'shear' => [
                                {   'shear_has_seqs' =>
                                        { 'seq' => [ 'target_sequence', 'bait_sequence' ] },
                                },
                                { 'shear_has_breakpoints' => 'breakpoint' }
                            ]
                        }
                    }
                ],
            }
        );
       
        say $hotspots_rs->count;

        my $total_seq;
        
        while (my $ht = $hotspots_rs->next ) {
            
            my $shears = $ht->shears;
            my $hotspot_dummy_name = $ht->hotspot_dummy_name;

            say $ht->hotspot_dummy_name." (".$shears->count.")"." [".$ht->hotspot_chr.":".$ht->hotspot_start."-".$ht->hotspot_end."]";
            # Get hotspoot fastq sequence
            
            my $target_fragment = $self->get_fasta_for_coord($ht->hotspot_chr."\t". ($ht->hotspot_start - 2000) ."\t". ($ht->hotspot_end + 2000));
            while (my $shear = $shears->next){
                my $seqs = $shear->seqs;
                my $breakpoint = $shear->breakpoints->first;
                
                say "\t".$shear->shear_name." (".$seqs->count.")";

                if ($breakpoint) {
                    say "\t" . $breakpoint->breakpoint_name;
                    while ( my $seq = $seqs->next ) {
                        say "\t\t" . $seq->read_name;
                        my $target = $seq->target_sequence;
                        my $bait   = $seq->bait_sequence;
                        #say "\t\t\ttarget: " . $target->get_column('sequence');
                        #say "\t\t\tbait: " . $bait->get_column('sequence');
                        $self->align_sequence($hotspot_dummy_name,$target_fragment,$seq->read_name,$bait->get_column('sequence'));
                        $total_seq++;
                    }
                }
            }
        }
    }
    
}

class MyApp::Populate::MicrohomologyParseAlignments {
    extends 'MyApp::Populate'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    use File::Path qw(mkpath);
    use File::Find::Rule;
    use Bio::DB::Sam;
    
    option 'library_name' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(l)],
          required      => '1',
          documentation => q[Library name],
    );

    option 'input_dir' => (
          is            => 'rw',
          isa           => 'Str',
          cmd_aliases   => [qw(i)],
          required      => '1',
          documentation => q[Input directory with hotstpots subdirectories and bam files],
    );



    method parse_bam ( Str $bam_file) {
        my $schema = $self->schema;
        my $bam          = Bio::DB::Sam->new(-bam => $bam_file);
        my $iterator     = $bam->features(-iterator=>1);
       
        my %hash;
        while ( my $align = $iterator->next_seq() ) {
            my $seqid = $align->seq_id;
            my $start = $align->start;
            my $end   = $align->end;
            my $cigar = $align->cigar_str;
            say $seqid,"\t",$cigar;
            my $query  = $align->query;
            my $strand = $query->strand;
            my $query_size = length $query->dna;
            my ($ref,$matches,$query_seq) = $align->padded_alignment;
            my @ticks;
            foreach my $cell (0..(length($ref) - 1)) {
                $ticks[$cell]=' ';
            }
            
            my @range;            
            unless ($strand == -1){
                @range = ($query->start,$query->end);
            }
            else{
                @range =(
                    $query_size - $query->start + 1,
                    $query_size - $query->end + 1,
                    
                );
            }

            $ticks[$range[0]-1] = $range[0]; 
            $ticks[$range[1]-1] = $range[1]; 
            if ($strand == -1 ){
                $ref = reverse $ref;
                $ref =~ tr/[ACGTacgt]/[TGCAtgca]/;
                $matches = reverse $matches;
                $query_seq = reverse $query_seq;
                $query_seq =~ tr/[ACGTacgt]/[TGCAtgca]/;
                @range = reverse(@range); 
            }
            
            my $seq_rs = $schema->resultset('Seq')->find({ read_name => $query->name });
            my $hotspot_rs = $schema->resultset('Hotspot')->search(
                {   'library_name' => $self->library_name,
                    'read_name'    => $query->name,
                },
                {   prefetch => [
                        {   'hotspot_has_shears' => {
                                'shear' => [
                                    {   'shear_has_seqs' =>
                                            { 'seq' => [ 'target_sequence', 'bait_sequence' ] },
                                    },
                                    { 'shear_has_breakpoints' => 'breakpoint' }
                                ]
                            }
                        },
                        'library'
                    ],
                }
            );

            say $seq_rs->id;
            if ( $hotspot_rs->count == 1){
                my $hotspot = $hotspot_rs->first;
                
                my $r_strand_char = '+';
                my $q_strand_char = '+';
                $r_strand_char = '-' if $align->strand == -1;
                $q_strand_char = '-' if $strand == -1;
                
                $hash{seq_id} = $seq_rs->id;
                $hash{hotspot_id} = $hotspot->id;

                if ( $seqid =~ /myc/i ){
                    $hash{microhomology_bait_reference_sequence} = $ref;
                    $hash{microhomology_bait_match_string}       = $matches;
                    $hash{microhomology_bait_query_sequence}     = $query_seq;
                    $hash{microhomology_bait_reference_start}    = $start;
                    $hash{microhomology_bait_reference_end}      = $end;
                    $hash{microhomology_bait_reference_strand}   = $r_strand_char;
                    $hash{microhomology_bait_query_start}        = $range[0];
                    $hash{microhomology_bait_query_end}          = $range[1];
                    $hash{microhomology_bait_query_strand}       = $q_strand_char;
                }
                else{
                    $hash{microhomology_target_reference_sequence}         = $ref;
                    $hash{microhomology_target_match_string}               = $matches;
                    $hash{microhomology_target_query_sequence}             = $query_seq;
                    $hash{microhomology_target_reference_genomic_position} = $seqid;
                    $hash{microhomology_target_reference_sequence}         = $ref;
                    $hash{microhomology_target_reference_end}              = $end;
                    $hash{microhomology_target_reference_strand}           = $r_strand_char;
                    $hash{microhomology_target_query_start}                = $range[0];
                    $hash{microhomology_target_query_end}                  = $range[1];
                    $hash{microhomology_target_query_strand}               = $q_strand_char;

                }

                #say $hotspot->hotspot_dummy_name;
               #say join ",",@range;
                #say "strand: ".$strand;
                #say "query size: ".$query_size;
                #say "reference: $start, $end".$align->strand;
                #say "   ",join '',@ticks;
                #say join "\n", ("   ".$ref,"   ".$matches,"   ".$query_seq);
            }
            elsif (  $hotspot_rs->count == 0){
                $self->log->error("No hotspot found for read: ".$query->name." and library: ".$self->library_name);
                die();
            }
            elsif ($hotspot_rs->count > 1){
                $self->log->error("More than one hotspot found for read: ".$query->name." and library: ".$self->library_name);
                die();
            }


        }
        if ($hash{microhomology_bait_query_end} && $hash{microhomology_target_query_start} ){
            my $diff = $hash{microhomology_target_query_start} - $hash{microhomology_bait_query_end};
            if ( $diff < 0 ){
                $hash{microhomology_size} = abs($diff) + 1;
            }
            elsif ( $diff > 0 ){
                $hash{microhomology_insertion_size} = $diff - 1;
            }
        }

        p %hash;
        say "\n\n";
        $schema->resultset('MicrohomologyBaitAlignment')->find_or_create(\%hash);
    }

    method run {
        my @files = File::Find::Rule->file()
                                     ->name('*.bam')
                                     ->in($self->input_dir);

        $self->parse_bam($_) foreach @files;
    }
    
}


class MyApp::Populate::DefineMicrohomology {
    extends 'MyApp::Populate';                    # inherit log
    use MooseX::App::Command;                     # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    use List::Util qw(max);

    command_short_description q[Define microhomology for each shear];

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
            {   'me.library_id' => $lib_id,

            },
            {   prefetch => [
                    {   'hotspot_has_shears' => {
                            'shear' => [
                                {   'shear_has_seqs' => {
                                        'seq' =>
                                            [ 'target_sequence', 'bait_sequence', 'microhomology_bait_alignments' ]
                                    },
                                },
                                { 'shear_has_breakpoints' => 'breakpoint' }
                            ]
                        }
                    }
                ],
            }
        );

        say $hotspots_rs->count;

        my $total_seq;

        while ( my $ht = $hotspots_rs->next ) {

            my $shears             = $ht->shears;
            my $hotspot_dummy_name = $ht->hotspot_dummy_name;

            say $ht->hotspot_dummy_name . " ("
                . $shears->count . ")" . " ["
                . $ht->hotspot_chr . ":"
                . $ht->hotspot_start . "-"
                . $ht->hotspot_end . "]";

            # Get hotspot fastq sequence

            while ( my $shear = $shears->next ) {
                my $seqs       = $shear->seqs;
                my $breakpoint = $shear->breakpoints->first;
                
                say "\t" . $shear->shear_name . " (" . $seqs->count . ")";
               
                # Only check if there is a breakpoint (this could be removed
                # latter)
                if ($breakpoint) {
                    say "\t" . $breakpoint->breakpoint_name;
                    my %breakpoint_microhomology;
                    my %breakpoint_insertion;
                    my $breakpoint_blunt;
                    my %seq_ids;

                    while ( my $seq = $seqs->next ) {
                        say "\t\t" . $seq->read_name;
                        my $target = $seq->target_sequence;
                        my $bait   = $seq->bait_sequence;
                        my $microhomology_bait_alignment = $seq->microhomology_bait_alignments->first;
                        
                        # if there is information in database about the
                        # microhomology
                        if ($microhomology_bait_alignment) {

                            say "\t\t","BAIT:";
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_query_start, "-",
                                $microhomology_bait_alignment->microhomology_bait_query_end;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_reference_sequence;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_match_string;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_query_sequence;
                            
                            # If besides bait target was mapped too
                            if ( $microhomology_bait_alignment->microhomology_target_query_sequence ) {
                                    say "\t\t","TARGET:";
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_query_start, "-",
                                        $microhomology_bait_alignment->microhomology_target_query_end;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_reference_sequence;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_match_string;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_query_sequence;

                                if ( $microhomology_bait_alignment->microhomology_size ) {
                                    $breakpoint_microhomology{$microhomology_bait_alignment->microhomology_size}++;
                                    push @{$seq_ids{microhomology}}, $seq->id;
                                }
                                elsif ($microhomology_bait_alignment->microhomology_insertion_size) {
                                    $breakpoint_insertion{$microhomology_bait_alignment->microhomology_insertion_size}++;
                                    push @{$seq_ids{insertion}}, $seq->id;
                                }
                                else{
                                    $breakpoint_blunt++;
                                }
                            }
                            say "";
                            say "";
                        }
                        $total_seq++;
                    }

                    my %final_type;
                    my %final_number;

                   
                    say "Insertion:";
                    foreach my $size (sort { ($breakpoint_insertion{$b} <=> $breakpoint_insertion{$a} ) || ($b <=> $a) } keys %breakpoint_insertion){
                        say "\t$size: $breakpoint_insertion{$size}";
                        unless ($final_type{insertion}){
                            $final_type{insertion}{reads} = $breakpoint_insertion{$size};
                            $final_type{insertion}{size} = $size;
                            $final_number{$breakpoint_insertion{$size}} = 'insertion';
                        }
                    }
 
                    say "Microhomology";                    
                    
                    foreach my $size (sort { ($breakpoint_microhomology{$b} <=> $breakpoint_microhomology{$a} ) || ($b <=> $a) } keys %breakpoint_microhomology){
                        say "\t$size: $breakpoint_microhomology{$size}";
                        unless ($final_type{microhomology}){
                            $final_type{microhomology}{reads} = $breakpoint_microhomology{$size};
                            $final_type{microhomology}{size} = $size;
                            $final_number{$breakpoint_microhomology{$size}} = 'microhomology';
                        }
                    }
 
                    if ($breakpoint_blunt) {
                        say "Blunt: $breakpoint_blunt";
                        $final_type{blunt}{reads} = $breakpoint_blunt;
                        $final_number{$breakpoint_blunt} = 'blunt';
                        $final_type{blunt}{size} = 0;
                    }

                   
                    if (scalar keys %final_type > 1){
                        my $n_reads = max(keys %final_number);
                        my $type = $final_number{$n_reads};
                        %final_type = (
                            $type => $final_type{$type}
                        );
                    }

                    foreach my $type (keys %final_type) {
                        say "$type, size ($final_type{$type}{size}), supported by $final_type{$type}{reads} reads!";
                        open( my $out, '>>', "/tmp/microhomology.bed" )
                            || die "Cannot open/write file " . "/tmp/microhomology.bed" . "!";
                        if ($type =~ /micro/){
                            my ($start,$end);
                            if ($breakpoint->breakpoint_strand eq '+'){
                                $start = $breakpoint->breakpoint_end;
                                $end = $breakpoint->breakpoint_end + $final_type{$type}{size};
                            }
                            else {
                                $start = $breakpoint->breakpoint_start - $final_type{$type}{size};
                                $end = $breakpoint->breakpoint_start;
                            }

                            say $out join "\t",($breakpoint->breakpoint_chr, $start, $end, $breakpoint->breakpoint_name, $final_type{$type}{reads}, $breakpoint->breakpoint_strand );

                            # Add to database
#                            $schema->resultset('MicrohomologyDefined')->create(
                                #{   shear_id             => $shear->id,
                                    #hotspot_id           => $ht->id,
                                    #microhomology_size   => $final_type{$type}{size},
                                    #microhomology_chr    => $breakpoint->breakpoint_chr,
                                    #microhomology_start  => $start,
                                    #microhomology_end    => $end,
                                    #microhomology_strand => $breakpoint->breakpoint_strand,
                                    #microhomology_color  => "153,0,76"
                                #}
                            #);

                            # Add to database:
#                            foreach my $id ( @{ $seq_ids{microhomology} } ) {
                                #$schema->resultset('MicrohomologyDefinedHasSeq')->create(
                                    #{   shear_id   => $shear->id,
                                        #hotspot_id => $ht->id,
                                        #seq_id     => $id,
                                    #}
                                #);
                            #}
                        }
                        close( $out );

                        open( $out, '>>', "/tmp/insertions.bed" )
                            || die "Cannot open/write file " . "/tmp/insertions.bed" . "!";
                        if ( $type =~ /insert/ ) {
                            my ( $start, $end );
                            $start = $breakpoint->breakpoint_start;
                            $end   = $breakpoint->breakpoint_end;
                            say $out join "\t",
                                (
                                $breakpoint->breakpoint_chr,
                                $start, $end,
                                "insertion($final_type{$type}{size})_".$breakpoint->breakpoint_name,
                                $final_type{$type}{reads},
                                $breakpoint->breakpoint_strand
                                );

                            # Add to database
#                            $schema->resultset('InsertionDefined')->create(
                                #{   shear_id             => $shear->id,
                                    #hotspot_id           => $ht->id,
                                    #insertion_size   => $final_type{$type}{size},
                                    #insertion_chr    => $breakpoint->breakpoint_chr,
                                    #insertion_start  => $start,
                                    #insertion_end    => $end,
                                    #insertion_strand => $breakpoint->breakpoint_strand,
                                    #insertion_color  => "255,0,0"
                                #}
                            #);

#                            # Add to database:
                            #foreach my $id ( @{ $seq_ids{insertion} } ) {
                                #$schema->resultset('InsertionDefinedHasSeq')->create(
                                    #{   shear_id   => $shear->id,
                                        #hotspot_id => $ht->id,
                                        #seq_id     => $
                                    #}
                                #);
                            #}
                        }
                        close( $out );
                       
                    }

                 }
            }
        }

    }
}

class MyApp::Populate::MicrohomologyGenerateBedFiles{
    extends 'MyApp::Populate';                    # inherit log
    use MooseX::App::Command;                     # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    use List::Util qw(max);

    command_short_description q[Generate BED file for microhomology or insertion];

    option 'insertion' => (
          is            => 'rw',
          isa           => 'Bool',
          documentation => q[Generate insertion track instead of microhomoloy],
    );
    

    method run {
        # Code Here
        my $schema = $self->schema;

        # Add library
        my $rs_lib = $schema->resultset('Library');
        my $library = $rs_lib->find( { library_name => $self->library_name }, );
        die "Cannot find library_id for:" . $self->library_name
          unless ($library);

        my $lib_id = $library->id;

        my @physiologic_ig_clusters = qw[
          (6/6|6)_left_026bf3db10f50d8e685185b89bcb58374698a8a7e70634feba080596bb738076
          (9/9|9)_left_054e832ff08babf24cc038d3e59d7c3e4f75c6c509b5e5faa5d031d85db65a1f
          (9/9|9)_left_0739f3144adfe85a0a56c82208d77e4de0471b2a7b6483c3bdfe9bd45db59e48
          *(3/6|6)_left_0788656be617629959a579184fb8faa1d31c46c87e9317c148755037eb58892d
          (3/3|3)_left_0941cb1254041ebdd4999056351500e4c4b875d5b9e7462ea629d92d527f060b
          (3/3|3)_left_0a422ba11005cb410512aa4ed5bc5262d62bf67b083b9461d7d4bfcd23331a91
          (3/3|3)_left_0bf4d80b4d0fa73b479399cd0f4cc4468cbe769e858dc45948ab05853ab3b1db
          (2/2|2)_left_0cd2c671909a144d829cb4457fd96dea5a0612c853ca8cffdb07e71c787da078
          (2/2|3)_left_135b8c19b925898343b79cf1fecbbb32d958492c5617b137e28d1a8e41c1cc63
          (2/2|2)_left_13a1f382b165b3a88bcc0647eb3152cbccb61c624e06194b6d96d1bc08b28156
          (2/2|2)_left_16814ab5a19a9dc9fcd53fc80b60f8e830b881fb18dc11511f08e2787447c4f5
          (10/10|10)_left_183209f378e484da0248688ab88e5e28a81930d14a140870718ee26aa8744c27
          (5/5|5)_left_184a14d3378b6a078071951ec50f9849e27e655bd4c58aee14d8881f461822d5
          (2/2|3)_left_1a8c460ace8cc3be6f442a305a4ba4d7b667d7169a0ddff4c23432de70f399d8
          (11/11|11)_left_1ba9622675529513ed942b8aeabc2d92d2896b87734bb1610099232df6b62137
          *(7/8|8)_left_1f3f6190c98b45fe9eea942a9a2a25599186baae3b973fd82c116aa9baf4f9b7
          (2/2|2)_left_2033d6fd2f60e0163aa112b457fe1c2521ee454eb2eb132495d601cd4d3a98ff
          (6/6|6)_left_22e27ed12d1146b1e224066cae81c47e32d9893615c5a68e067f5749c9c070fa
          (3/3|3)_left_22f8fe667a763aa517ed15ba4172665c1e2ada714ca83a3b5326fe6c237fef32
          *(13/24|24)_left_248f35feea6786130a339b60bde8bc4a8e2fbc85f18468a6451ddb5f4ec09e78
          (16/16|16)_left_25858a138557a96f471402637104c4cb8781e3775c8ed467fc115808ddc4aac1
          (5/5|5)_left_267dffbef45dd94b3a46b6cb9475c6b017abe100859d8f0e7633b7d174647987
          (3/3|3)_left_271a9c03abc402dea62dd495a72a5a4e5883e62649458827d45b013a6bd13389
          (2/2|2)_left_27da4bef1e5c1a7c9d73ac87feca89c0d065b3b8ee4da3f462e5217cd8e6b4ea
          (3/3|4)_left_2876042a7e274591fc885667cf4c788abca6cf5a8f0c7b3f2af0bb658777f9b3
          (6/6|10)_left_2a6ce32de73b26b68dc369adb51e2d8e42d57b19baf1cbfb10255dd0e945543a
          (6/6|6)_left_2c0c59b15c06d4bef7b59bd62b4c5b19f51b856862e783428a106f7185a9624e
          (17/17|17)_left_2d40e74b91563b7e2e67b6281e4988585e92c0f652fe755d26698602e532bd9a
          (2/2|2)_left_30b6e482184c0f797718784ce47011a6509cf3b05d85f2d92be803d2b9023f50
          (2/2|2)_left_30dc006023b0eeba986de1ab2881bde48108da84f20cc64aad109d2e1d552a91
          (7/7|7)_left_32126f866503c2b7fe8e6381ac21e4a076ffbf1591317f27203aec715e029786
          (4/4|4)_left_324278149fc84ad9a818aa765cd591f35692e067d716a755461ff04876c9adac
          (2/2|2)_left_385b2ef2f4a4d812f8293418e452932514b142ed60c00bf1582acf40212fccf1
          (2/2|2)_left_3bfcee331305768c1a02d93b46ed458a8be29f1d274503f42c909dec62c3d14e
          (11/11|11)_left_3c8bb6309c27165e0e52ba3810e26e84d7032313cb01ed4d59eb5e28d55b4961
          *(11/12|12)_left_3e9bd87e42e95f03f6af46c47554dd0b029878b436662287c86db55768bfe972
          (2/2|3)_left_3ea11f7845e3dfcfb667828e1419e75e0185abbae57fd0f7582345c6532e31bf
          (9/9|9)_left_458c1d0bccc234e42e8b94eb489c6d5f282a37e37d4759abe2229a714454938d
          (8/8|8)_left_46228b22da16392246556afc625fa99c99f67e05e5fd47397f56582eb9314d63
          (8/8|8)_left_4bef0047d1d7cf374d2465bec4a7f1d9acc964210ec18321c2d035929a16bde8
          (5/5|6)_left_4fb9774c70057fbe7dde551e3baf36d0a87bf8d79ff83a7acf64affbaa975854
          *(7/12|12)_left_5200833591458c38093eff74f5e327a137013f8ac546565866d229e02e035d16
          *(2/3|3)_left_53d393c84dfedf2a5736acaad2227e9835674bc085b220ee624b3cca98ba631f
          (4/4|4)_left_56dabe05754afba098c658581bb852ecee5b0d9c2720a73326bdfde6343e9f2e
          (4/4|4)_left_571e200725d78ff1501a5f2a406c02fe7f38daa4433fb8443aa5f72ede43296b
          (4/4|4)_left_58bb0ea915e30c81ed782b8daac5951f26c624fd625a091050a57f0e1d1fe9c8
          (7/7|7)_left_5d5321d6dda479886b4e8cedc56b8317c90de5199ad3834ba70bf3b107abb063
          *(3/4|4)_left_5ec06601dce385a68c55d3dca62a1c1aff7668898345910cfb4b896020a4c0de
          (8/8|8)_left_6488d21fa1c5cf2b7f0cbc1e9267a218e92369eee853841a26cbd664744317a9
          (4/4|4)_left_64e37345dcfe6766b5344ba2a9d7c2a3420907129dcb604afc62702e864b9f8b
          (2/2|2)_left_664b2cb3650956d6ff0c66c0099a86e36d2af208bc8d9bc43e94463c147e8f14
          (9/9|9)_left_68b7e261a4b189225e1358a1ed284cb2bc813faf7ef656e0e4000863ec06d4bd
          (2/2|2)_left_69272b8c5551fb14376dc6298d05a6f3cfb3efd0936664657fcbc1a1df71961f
          *(9/10|10)_left_6bac6dc609b95a0830a78b5f8640a2a33d09d192bd4124bfadd289bb051d5d1e
          *(4/7|7)_left_6ce03784516065bb86251593ce34ae5dfe4ea1f60c9271b8fdf63d7d42aa71c0
          *(6/8|8)_left_70e460dbfd122c6d93ba71ede8e7882fa89627b10506109bf6f5528ecccf8784
          (6/6|6)_left_75a322350c0978c58ae63d575625f18b0cadf2b3e8b9ac9dcb04f84c0ce022d0
          (3/3|4)_left_764399940217b9ddfb22c896ad559cd16b76a46ed2416ef2f36fd9e30dbd48f8
          (2/2|2)_left_7971b6dee3066dd285040f5abd9f88dc3c5afa6743c2103c0223547a1c591917
          (5/5|7)_left_7b6ca7ad1f384f56c6e623a0736ea44f1805a9e941de25e6d5926ac41e92e6fe
          *(24/27|29)_left_7e4785cbd85079ba42aa7d96a2e4533ad1abfa5fc6319c41aba10b1d1260a106
          (2/2|2)_left_83728e22ed43a539642a2a5d76e5f192f71abbb705c921b276463166f4795d86
          *(6/8|8)_left_8426d64cb99173181a68d538aeae3816782e49221530b2feef87e7edb5b97e2e
          *(17/18|18)_left_849d4a6d2baf999f9bb113b75acfd7ae9135e61df3699cb57d6cf6ff6c3f5aee
          (9/9|9)_left_896be713018885df6e5b2a19beb326786ae03483588fc6c608f1fa7b089af57b
          (17/17|17)_left_8a0657e68cc0ef37603884ddb3a8aaec8c4b2f2149ee9d24301b41aec3156a6d
          (10/10|10)_left_9491747ae6465972c7141451fa4327e964f923a34d4295dc12e74320bd6da72c
          (10/10|10)_left_99815fb597547ac8527acd6dc471912f91119a68fdbf8d65bbb26de67924ebcd
          (12/12|12)_left_9ee015387c1a8cff117062ae595de5037f58f59a6cf8bb70d5763c935c3b7b2d
          *(2/3|3)_left_a357cd0dada8a6194cd4ff73f2ad664c8c746201b489f8df9919779a21cfadb4
          (4/4|4)_left_a47b853dd80a0d541925069eaf1f36808462596fd91fc2ebc19d9dd10dae0a1f
          (2/2|2)_left_aeb4aa6d57951cdd4aca1f28ea07478d484c9df0f5831054b2f6f0e24c61fa36
          *(3/5|5)_left_b1c0f712a23d1d17cb023980457986e47a568865d6115d6148a4a1bbfb7739c9
          (3/3|3)_left_b3024ae7611a0c8693f17df10a29b1e58b1c4c954920bcd92974035add024650
          (4/4|4)_left_b4dcd5a9eceaf348aadf9ea341399469008bfaad234a66f9045e485d713c7647
          *(7/14|14)_left_b68553ff42c585cfbc9c757694706dfece1eb0d61c9469002f078ac9190c946e
          (3/3|3)_left_b7c5832c8cc03fd4ef5b54b9159b22e4b5a0252a126035ab7f6fee2714b14b0d
          *(13/14|14)_left_b901fcc38d80d76516c3ba7ed6ee38c1a663537557a88914a0f68c0f79754c31
          (17/17|17)_left_bc6de5762ad0391859159d731d7da5be7b98d198cc6479f129e7090dfafca879
          (3/3|3)_left_bfecdc74d02d8dc3e10c7766d8a7437b5d9438a482e151bd51e4804f961f21be
          (5/5|5)_left_c22db692b395e285e0cbfe3f92867b6dac47f2a20817adc80a9b84bc90008b86
          (2/2|2)_left_c2304f9e083608369d824e07bc5cf189b12da98495000dceb6541db4f75bffb8
          *(22/23|25)_left_c68a2934addad9c4f4272e8a386a596582bff31057f86446429846a07f51fae9
          (4/4|4)_left_c8e595c8f0346469dd0bd02b4a77daeaec436227f6b37324bc7a2a0eee02619f
          (3/3|3)_left_cadbaccb38cc0d0d012d1356bfb5c2624af00db0f68a5fb6c327f428ab70bf8e
          (8/8|9)_left_cccebe06097ce04ad62ad3053cf1263096e90f36eeb21dc9f5c8bc4d7f213a5d
          (3/3|4)_left_cdb1ef98d15928b4aabcd65d9a05f3f54588d0c34233d4a78bd5e0cd76d430d7
          (5/5|5)_left_cf824c349540ff14d3e2b8582b2643b523349a06ac1fc27dfc692383988cde10
          (4/4|4)_left_d1153b482bef52da7c1f66785a894feb4bc9bf4835296dbcdd94889aea241eeb
          *(9/10|11)_left_d1358b11443479856ba2297f50eda9b4e060c0cede76626c493adad795f8a0c4
          *(3/4|4)_left_d57e6265bd83f039d4a7d91eb29a6a6bc0e26c00991facd4d084cee3bf5d53d0
          (16/16|16)_left_d73a63685f7b934818f622a2f72752c6fc406680e91e07155a9b55e24baae937
          (5/5|5)_left_d86b38bc98958fad2c633789fbcb8d908914427c11df3fe76b267bc44a31077c
          (5/5|5)_left_db06daa30114571526e28d3764e30322a7fac5dac15b42d9725f4b4384842ea4
          (4/4|4)_left_dcbb75e4e0d64305e4c6942de583245664569e621a563e3afed1cbba18c92555
          (6/6|6)_left_e28b55114a7ab22f346e31e49b8be46ed5f11784703929fb1c703354dac25c7e
          (4/4|4)_left_e37bc2ab7135b2e117c468ae2167edf7ac9f222c160b230e9c1e78af717c9a59
          (8/8|8)_left_e9dc9c9871bee441d5dc0dedb754dcd05c721e55208051bcfc8a65c5b0381fef
          (13/13|13)_left_eb0aaff861ce4de00fe96cd006c0d81980556f5ade2939ee1c96e65072bce5ef
          *(2/3|4)_left_ec3afa6d01d23f473b631fc56970709f6fefa69fb8f874dff52a9c4cead1f3df
          (3/3|3)_left_ed933ec9e2c9091d3f05417bef9dd7a9ee24e7bd05a774b9f655e357a91f44af
          (5/5|5)_left_ef76c03738adfcb60c5a4c59d4a40f6c088b27a68bcaef056071b7a8f35370eb
          (24/24|24)_left_f2aee7d3c0779ba081ec12b29d035093ebf488c2debe48bd71689db68f0c183a
          (4/4|4)_left_f3057528f45eafdb4b437f833b5bf49e1bf131cdc02c35a30f1b870e8190b663
          (12/12|12)_left_f617152ded0de4f3a52f1d98cd999aa37668dc1b4fc91d09ff3e70b5b8c90cc3
          (7/7|7)_left_f8a1fd0982c2227ba9399da4fec0c93a45f4efd540ea76034c2bd5a805f79196
          (4/4|4)_left_fd180acd03cf0f194121ace908e2c3987ab56b0878c1b37160380b147e2a11f2
          *(9/11|12)_right_04900aae629d786929c6d426c3f27754573d5d3aa410a58c1b3a898872b2ee44
          (10/10|11)_right_083f1bdd5f6b13caf7d419cfb874f2c0d197fa2b2e198621ce407ff2e2d8e1c2
          (7/7|7)_right_0857539353c00c2d9234494a4e26c022067db8f6b723ce4c32491c9908b97150
          (5/5|5)_right_08647541a4d5b16fe88d83f0b8b9e41b7d8b259bd7f6163d14389751f9389c43
          *(7/10|10)_right_08bd9cee5e446f46f7491b94bea7d7269edc92ae7592071c219b2caac863de70
          (6/6|6)_right_0942648f9b17e6b4a2ed59805a0a61ec5ca4749c8b10c29a2947db5688d89155
          (14/14|14)_right_0a814e2d900cc9d60bd9187d7856b067954a790a4367d84acbd2edbaee13c5ee
          (12/12|12)_right_0bb663cca265e53b6bbe7b57f5e38c402e5d00f9f36237af9e2f8dda533cfde8
          (3/3|3)_right_0d28aabc13c3d9fb2ffd63ddd09b96376fe5e37d9584a1440849ddf8aca4b8af
          (5/5|5)_right_0f46e4caf16126b84844be8ee9b29bec73197308c28180b59d160e8641d01496
          (12/12|12)_right_0fe8415451efd6a4088a601eb6f35a603149eddd9b537e7ef06c602d92e9d9e7
          (10/10|10)_right_1044e385d902ca5b90a9daa1531a23d5b08e580075b49c66157f820c44613f23
          *(59/60|60)_right_143768d8291ee20a0692796725af89afabddaae0cd15034807a013a30e1c1e12
          *(24/30|30)_right_1828f527f21adfb392250399810d3714e1da7d9804a80185ccbbdb7c44ef93c1
          *(38/39|40)_right_1c336333077d3158c5f56cb92be046bf13db7df88f8aa6dd7e9fd07143bd7253
          (2/2|3)_right_1d5e561bf1e54fa49ef35a291eb5e4d0635fbafcc2170edbc330cd1829286707
          (4/4|5)_right_1e6d8375e32dca52584d9a54392d7520a8e2c3cabb8b901f3f7e0031cf56f974
          (5/5|5)_right_1e70f1d07dfb5b30123cb26b9800e70c5eca735a37fdfe441d620df320fd4607
          (11/11|12)_right_2076e5c9987f921489fbb0a1c96494a1879f7babe56a2b1c2e49c52abc5c5b8f
          *(18/19|19)_right_215ded978641f9e7d64a0bd126d44d8bbc8ac8567fee3243f2ad131bcb20d863
          (3/3|3)_right_25881502f8ffe1f4b231df9763b58f6e7068425a476b9d11d58262cf7c5f544e
          (4/4|4)_right_28bcc90cffe5d94eee4abfe6ff9d7620ecb890684b084920ae95a5b5352869c3
          *(8/9|9)_right_2dacc19d6460c0b4363d4636fa05b8ac4909628074e9516886d710cebeecd352
          (6/6|6)_right_2df6e731f11b25179360dab5a34442c070996264a5c38cd3ab82765e37fb6188
          (13/13|18)_right_2e08aca86875e7dbe71336e92603a341e7ca23ed3c5639015b1bb2306d16cacb
          (2/2|2)_right_2e7c1f7d64927e008b66e22045b379fe32e90587f17d560f61e42c1a49296647
          (4/4|4)_right_3c8223066d6146c4bb0ab94cb6ef4343987504b035bc757d2fa4022a1fad8f8c
          (3/3|3)_right_3f649b1daedda6c8fcd0cca2d419e03312053cd1e9174faa7e37096fe5032bf2
          *(10/18|18)_right_42359000a979547353c0ed1e14fa936e8a889b0a295bceae77bb0b0e3ab4d5fb
          (25/25|25)_right_46764ea2eac22c525b55c1d744f6faf50807434842844c3f9d9c3b0a5e84d4ca
          (17/17|17)_right_49000ac04c7625234896e81d3eb104213b550d79f09eaf3368f4d896ff6a0cc7
          (12/12|14)_right_4ae7ec1dba31fcfa38a7e15f4e0d1c959c102feafbc69f1bc162c53a44fd454b
          (4/4|5)_right_4b5e4638bf6bae63382960f43ec674dc5b41ef9c0fa9f074c01772d70c8a10ca
          (10/10|11)_right_4bd4694cdb9c6d0ed439268ed431d243cb28bfad969ef00e28349f43d4e89671
          (4/4|4)_right_4dd119850335988bca72727903ed3b43b8798646520cf1d0b4159db155a5f5af
          (4/4|4)_right_537e6c83a5c5fea3fe3ab5386b2b1cdb7ebc2c09a0d739fdd3f0569779a408bf
          (18/18|18)_right_54871431182511b1051c610d153f992a13d717c50d07a5c6eec657ad3731c358
          (2/2|2)_right_57fe77ddb08bc7306c1aa8d77042811343d1c1ec0a32fa6c029b7b051a100c72
          *(16/18|18)_right_5c7410338c4be851fe9948becde2d9eca6fda70ebbf75c38f4f5908448e9ff72
          (8/8|8)_right_5e6b60f258df9d3965d764e734cc2b5992d0c1e94a5e1d90cad9a1d58d3ffbc8
          (3/3|3)_right_5f7a8d50c803012957a0e7eed816a02ffcb62a6f29f6853ea5ab9298789c899a
          *(23/24|25)_right_62c4bf699f1ad80ef221ae0faf936ed480300e9725ca2ffc171c2a24ccc6a71b
          (10/10|10)_right_62e66a4ff2e6f4b5b2374884025b0192984ea4838ac5b25059e5f1ab1ef70300
          (18/18|19)_right_6425e8c65fd491a684864124e48b34dd4b731aa46a03af8bc9d4c5ade8a472d2
          (4/4|4)_right_67ae7011c55646643819b01309c4ef33576a45400c81a88fb1bff966e456616a
          *(27/31|31)_right_6831146d6d39ca1b4659dc2f5cc8f7b1ba32b8b3358696b308e04e7398ce4fb6
          *(21/22|23)_right_699bf12b457a945135dfa0ab2637a663b2cd4f041d70c3b9d541149e34844d3f
          (11/11|11)_right_69e7945ffa6983aa7ee8797d9acd984970eb707f832328c3a8131e1928960fed
          (12/12|12)_right_6a82b2f7709d63f8495436d684443fc75bd3917ba8571b5e8726fbe7da435e19
          (34/34|36)_right_6a90263af126594ab85857d2fc7bc28f20d9b51d1b6e74196fa98d9ceec51de4
          *(21/23|26)_right_72d35a557220a361111a064dd88ac590c04966ff863aaf258ca92df6dcdfb1e0
          *(7/11|11)_right_73b42ca3f55128ee4ac4e975792694a8fae2b706097b688c5b9d5aaacbf9fd3e
          *(14/17|18)_right_750122a05b1a810056d2740d04853ca3e2fa6e5f1bd5f47b057a4f8f39732a3f
          (9/9|10)_right_78e3a4194234157f7c84f4735dae5642bda9c3002904bd28002435068e668446
          *(30/31|31)_right_7a3aa6a874a05dee90c9b0535cd1b63f93c3e6a74b20adcc7859f8b497b7b514
          (2/2|2)_right_7d01b18c74db70e0d6696067b049a8f79680850ea650cb8dc91d33e2d44acd0e
          (24/24|24)_right_8334e3052b96b70e3f842f1572b0b34efcee2956dab5b87e9d75ef09dcc1a0de
          (16/16|16)_right_89e08764a7b36e0f154579dd02f7836003201348a10ac3419bde4a5914ea12fb
          (13/13|13)_right_8aeedc0758ca4cbdc9e508de0e4846395940efb857455e15ad23a6197c930755
          (2/2|2)_right_8aef01629e81552374a0e21ba22012f2bb5ce007e226c36bd6d47149b0fb2425
          (12/12|12)_right_8d95fd563f59710177a074e23442b48b0d1f63d4f237f4b8a2883db94738de0a
          (5/5|5)_right_8f9f7de92e3cb0d91cece7ec99e13ecc1c813fb08606e837a6abed96ed1c7c82
          (2/2|2)_right_907e63ab87495561e3ba219f3aa455ae66533caf09946b4af2b3fd1faba465a8
          (4/4|4)_right_91f75eab78b54eca350fde98d172b51620a33fae35bc361bec3ad6b128f7b828
          (3/3|3)_right_93e1e2083fe94647831b53ac94d3b4eb523aefa341e60d22ec90f921d0e2a0b0
          (3/3|3)_right_9db00def9c606f97763a12fd791f5fc73f0c383968e2553f6fbba2388e87ef33
          (9/9|9)_right_9decb86d4b3e214708a09e2a41f1f39328df2b54d9add382b370d57314b6b65b
          (22/22|23)_right_9e3e2888ea24a810ba2684342466184853c51ecb5c2fae7c897a3bf34ac36ccc
          (13/13|13)_right_a0ce16070f4a627e5a7cce7cbdf7f80b725afda76d4e19eefc6c5b7eb8c1b81b
          (6/6|6)_right_a5b5a51fc340110ec13505ae96bcc984e865e769a127c2b0cdda5469786c2417
          (26/26|26)_right_b2def443caa89ab48f992dbf88979a49744d194359094c27ff01eaa0f6118e8e
          (27/27|27)_right_b3fec54fab39690f8e14a2ce5cccbc9d1bd60eefe01f4f97db62387afebe89b8
          (6/6|6)_right_b440c88deefc2b017bac7dd1714d8d7d9d7f634577198c54bcdb23a0102294a4
          (16/16|16)_right_b499a8ded675bb7a09a620730ca57e5c85bf79801d6e681756472284d5908279
          (17/17|18)_right_b8d824ee6947c4f4c9ee7487748f1f1b36130106462863d69d4ede730ac3a27d
          (5/5|6)_right_ba68d4df90d1dcbd3f13535549ae6a43ae35551f8e8ccd6f32110ed9653319b5
          (9/9|9)_right_bd605480c6f5df61bbd9d11f7ddb07e4c8be82ef7ff1d97e7884f3b71050dffc
          *(20/21|22)_right_bf2ab014a44ab6e88cd72ba4664a6d6c7eb202ff78fa53460314d47bc7513df0
          (27/27|27)_right_bf89343fd77305a8f0317b90f59abb3428278674efee72ca64dcc247877374f1
          (7/7|7)_right_c53331edf14decc6c1d523ea480e79789b513ead3b8d63f2453967a8764e1b24
          *(10/11|11)_right_c68576cbe079cc7edbdf4bd23455f0ad98be326885e126f5c90c6deb0c28c3ea
          (4/4|5)_right_c7dd11ed88d31546e5465f9d90a15803bef44d41bd5abe836b3cd1d99342b923
          (3/3|3)_right_c84c2b7cb9678b1c41b8601730b9033f076425e36063d6d1373ba698cf2e8736
          (4/4|4)_right_ca1ecf053d9a2adf514cb9a9b347fc2fbbb902805eb88ffdea0f4d3b12b87b24
          (5/5|5)_right_cc186d3cb9059491687cdc950c57546e18d7d071b4fc73dde0113cc106e95c7d
          (7/7|7)_right_cc6485e8785eab650b858515c85d16b0afcebb7296d95d0103affe6e029f83c9
          (6/6|6)_right_ccc3a9507424620c3df1b2a03bbbe417c6a18320e6ea54b0e48ef49e8d568377
          (18/18|18)_right_cdca2fe7b8dc9be8ef1d2693f247fe4a0539fd75803b7e6a7498936c5d90944a
          (9/9|9)_right_ce962c85863dc54f7d3d80c7a397d82893599024d53c286713a887157839d44b
          *(25/32|33)_right_cebe418669acee1b084cb289c748b7225f477065d8198c091d25339faa0d3c73
          (5/5|7)_right_d2b194add5909887a284844fdee5761ffed418ed020f2e50a01a7d49ff720044
          (17/17|18)_right_d4eab388cf3cefa926054a9a0202d84d94427291a428e08a8fe3c722d2e9a704
          (16/16|17)_right_d6e365c0ac6449d5ca42c085d830873691497dd714989eb5ce15c446807e4c28
          (18/18|19)_right_d704ac854103c5ecfeea99becbc0b3633b5ec8fbd7d89d9e01a7f52e88f50d38
          *(28/29|30)_right_d81195e77cd12cdcb3ff4c815d8610258f8707c98044c20035d3d9b073509055
          *(7/11|11)_right_da6154045fee96a705a0c346ee61cf5d14d1e33d653f2bf69070746c55fe8978
          *(26/30|30)_right_daa2b4231115cd9ac9ef3b4d6a188e68b1cb410f3f74448419a003ab4675ae63
          (4/4|4)_right_db03913326e8818505fbd2e06b5788c8997569ee1d9b6b55b7adf6303e7526b9
          *(12/14|14)_right_e0701d3f481f70ca5db634ef537b0c29edae0903e61c04c023ff9802f69f6526
          *(12/13|13)_right_e35fda45a25bd7bce8edcca62fd848420fec1102ef43a4b1b0e0e2cea95c582b
          (6/6|6)_right_e450afc5d7dcc4948aba75e5d7ffca19443021bfc8dcebe6050867577fc5262f
          (11/11|11)_right_e5074b057dc25b742664920c3e4dd3813f70d6b87fb4c62961c2910ae46cd9c3
          *(56/57|60)_right_e68e449c4b4b2c378a9b365ecde2a021dbb5a895e5e0ef3552e5c9fc5580ad8a
          (8/8|8)_right_e9d8bcd7c58cd9ecdc65278bc0ce8b27da7cb0cf75a03e4e80dbb923f9d16497
          (10/10|10)_right_ea248453c310dd4eb482d771f6915065e60e9978bb22e8b5d7de6cd35478485d
          (19/19|19)_right_f807ea6475148824833d6d263a6940bff81f3efc01b000c02087f6fcf1a432bc
          (10/10|10)_right_f8100898f0cfea8222b56280990c47527d66beef9dcea06c6d95e10330b4a7ef
          *(4/5|5)_right_fe055ed6e5ece80d7207b915cfe73c7c29fde5d4f887a5792c304782d20009e6
          (2/2|2)_right_febeb19fa9ae08b1082867f1ce03360f05bfaec9502de4379bd64f8f9b67f5b3
        ];

        my @non_physiologic_ig_clusters = qw[
          (11/11|11)_left_09af8bc207a0b7f9f179db3c96b6e84ed70cea39d8cff8417bf5544de649ba57
          (3/3|3)_left_0cb74e1f5d2002168edeb8c9be1c2ec6e2e69624b69f10027bac997fa8a611c6
          (13/13|13)_left_15b96dbba3c7c48e438b3635028496a1cc0776585cbe9b4e4accf19ef2eb050f
          (5/5|5)_left_15fb91482344d55537df65a73f3e502cb8f9e46510d2505bb5e6b4f89fa9387c
          (2/2|2)_left_25bf91dc4269b7b5524300dfa0c510ebcb76501aec3a202b64d892612fd8506b
          (7/7|7)_left_2aa6a803f1353c569b7d0c83783d233025c8096a3baac1604bf8dde37f2a8c92
          (13/13|13)_left_2cfc6a7c3cfb46c5607afbf1a612290c75614655955fef12d761baa9093473ae
          (8/8|8)_left_3a1a5bfe359b394a4d9d1615304bdd21fb3a313a530d234ee120da0cd35adcd0
          (2/2|2)_left_429c1cf47feb17e1c774d4d1bfd6a0660c1171cc26bb8b2359e1b7a04b37c86c
          (3/3|3)_left_8895516703c60b6d59cb1eefd8a25767fb26e351f88d571aab4ef6463781829b
          (2/2|2)_left_b4fbcec2ed1780a3d9e6ea14f58c6917232b8bd09417adf5676389e722c8a28e
          *(11/13|13)_left_b8e16aef0c6f472fefb8fe76764cbc6f77b628a627f3ac18ebc9febfbabc7fe6
          *(16/17|18)_left_cb0163cba2454b7404982bd7142397d615b6aecbcc8d1dde88203f42653ab1c8
          (4/4|4)_left_f5498d37bbefc96083cac521d2c5579bbad550985a963d5213701aeac3175fc1
          (4/4|4)_left_f5f871035420cda2203a5f9eb42bf24d7bd14bd71e01726389e594f64e835c2f
          *(5/7|7)_left_f99c76095bd4713f3907e3b942a180d90bcebc9d9dbb18bff9d72e23b86c4f1e
          (30/30|30)_right_0175b165cfff73144840a155f915fa896d4cbaaf10e544759178207ed0213e9c
          *(23/24|24)_right_2bad5891c759da348701864efd611c5ef382e590eb13327fee25fed77ea6a48f
          *(30/33|34)_right_542603e5ac33623fb7f7aa01a4ebf9b5e678abed38cce592d75b6205f3344f88
          (19/19|20)_right_60ae33a9c2c0a496e2f491b8cb047e5f4217de89eaa714686f6eb00eef8301f9
          (3/3|3)_right_8eb0e5cf6f7fc466a2a648d4f5251e8c622d86913c2573ca52762f6eed4d5fac
          (2/2|2)_right_9d441f02e25550d5eb57418ebab7d7c7898f3e098ca10626f0ed119f58af7a5d
          *(18/19|19)_right_acc4188746a5f76e7ab6e0591a0b80480f063cb58bf3b2818c77bd149ad5153c
          (4/4|4)_right_af9f15226697d1c80bb0059bea4adde8ea1f7b62fb4b676e85bfd752c4f1cc8a
          (18/18|18)_right_b381674a8e322c14caced024ef2fd3c4e2d98db2021b53818b139f6d0d5781de
          *(28/34|34)_right_bac7537ba6b6495d03d576db37217d577bb63825593a65aa89497993db927a4e
          (12/12|12)_right_c9a1bfd4b4f763f83a71ef9b0d0aecdf3656cf1c64205d6618e8a33d56a27226
          (9/9|9)_right_d3b490c847ff3d246423f0a90e89f06aa0dc99fca13abea1fadae609e86363a1
          *(53/54|54)_right_d3d7950a2a19c3863276bcdac1472998134a6c4b0daf1cd522fdb85a494f7317
          (8/8|8)_right_e14dd1ce9332a171dc89b799e61d069996ca296a24bdbe023a3f6c432804d4b6
          *(20/21|25)_right_e335528735fd44aa3115bf70d50ced15c54e1bdbd1292a0a1ca43d32753e8615
          (28/28|29)_right_ec4d0de1538c5e93b1ce5d381435a83ba9c0195a640bf523aeb06b8399a3da58
          (23/23|24)_right_ef6f498fe569c15713d4cd3577c8650c80959d3a7e8d37e80ce33333aca113ed
          (8/8|8)_right_fd457e3b344ca7580412a00bbce351badaae2db786b3962ed471a7d856e529f7
        ];

        my @off_targets = qw[
          (3/3|3)_left_048653d5178347f54d89084e92c6b04915fd9f45369fd033175ef227e0511b72
          (5/5|5)_left_06580f8191178fe031acc8c263d0f6ae32b052869ebb440f9838c011e17acd6c
          *(21/22|22)_left_0c43ed86a4da926d1d55a9fa5866b1c813712346c98969da67e0705dd3ccbe1e
          (2/2|2)_left_289b183489a55b3e73193989011c73bbb571e95aa6a001cf8f6cfa9b297346ae
          (2/2|2)_left_2a77a413c079800f7bf173e2932cf52605c5a36b2d4b4e30d280ccb2666258e0
          (2/2|2)_left_2c057487dbbbadfc130e64551e2f331c8f6020e487bb2534f9074ea346ac34ee
          (3/3|3)_left_3cd33500128f11ed70ac78d272625fc93f6ef9574098103c9c8d86652662cb1a
          (2/2|2)_left_4a63503d2803417fd6d6a1a5f9a79b881cecbb892f9352da8785cc2595f0dcdd
          (2/2|2)_left_52a9d2150c636df78104db49046129a0c5bb7c580cf0c12147b43c41395d80a4
          (2/2|2)_left_67e949950eda221c8e2663968502c75ae7d6e892c45843e1c6d12a907a2fc509
          (12/12|12)_left_6c03f7b169af21253e2349fd68d3b9c77f3502ea4f3cb37a8d183792b6c2f7bc
          (3/3|3)_left_6c5a0a16838b756b8638a9fbce740fc8f58ce092886937eb1505532eedcf52e3
          *(6/9|9)_left_7a413c7377d0b1aa59ffb646460e3b989383d2f58e6761755b74ba60c4ff67b3
          (5/5|5)_left_81151f538c82d3abf89df286eb209a510b541dfb8a8543fe8c8130092c9c5466
          (2/2|2)_left_8573354b5d0dcbe7294640ae402eafca63c38485f1d19991962b512fad14f3bc
          (4/4|4)_left_8ec67cf6682a8d504d10aeac9f7f0fc8926585ef8539715c50a77e6275389adb
          (5/5|5)_left_94bfc0141fa68b1a04704184f4dbf39f2e2b97d34610a31671a9999586e47ef0
          (3/3|3)_left_9f00aae77d282af7abbbca88facc53544f5b8167957b6eef42c84e2d4efd1e42
          (4/4|4)_left_a2358f3f09f7db385dba7d5b8c5efc6e91c77a6850c5802d4ff95bddc01a0e83
          (5/5|5)_left_a8aa34a0cb5ab639d4771a4fc6949a3525d5d9d680ffd9798608978c2f5b6a1e
          (2/2|2)_left_b96ed4d5615513d15ddefce179ac3ed461abae18c5fad1644dc76182a1c6e534
          (2/2|2)_left_c9126aa2fed69d84b5acb578e0ec895d0d0f489a5fbd8c05ed0565eda2e6f87e
          *(28/29|32)_left_cb46a536b58296db6c2bae63cfd01c7bf530340452304f0fbb2385943052f7ba
          (2/2|2)_left_cbdd2ea8fe69a6da1748fc6f22b322050ba311878c51cb58bfc638cd53d2e2aa
          (4/4|4)_left_d6828cf349fcc0ef047acb1b541b55a713078acdaa831240c0fa2594e9fbc7f9
          (2/2|2)_left_d96fc8e2cc313ad74ffa398ef57206b1f3f9a359e0b41fed422afcf7b492ac15
          (2/2|2)_left_dfb19c46dab38dc0a5c8270d18fdedee1f74ae9aeb4a165da5be725f6141295b
          (2/2|2)_left_e1d175dd1ec769e8b481412de4e2028ddb4f547d3d4348f5b10d09f7d3b9c4cd
          (2/2|2)_left_ebb8c0f5f3ed64d40ad425cf39eb844e19b48df0c5eaf450218210d10fb84abd
          (4/4|4)_left_fb8b68ec58b1fb6ced30e960902419bb53884e7e40b57c726e8ea5c019855d74
          *(34/36|37)_right_012be23f684a2258f9350de8cfe67e79ca172ce1eac8167b9da5560d466ae1f2
          (3/3|3)_right_05908693020ca6c1d1afa14da6b1057360a09236b4fca115952426da407107b3
          (2/2|2)_right_06451247eefb326774bcebe53c50102fe481429721ef14ac93f3e2b8a2b770fa
          *(2/4|6)_right_066c3a5f425e9a37f091e5e298a7d44629061aef223434dca95bba4fe2fc4ae8
          (2/2|2)_right_0cea8521ab66d5bc32a282b42e713fd41dcaf950bbaf30e7c09886bd4bbc03e8
          *(2/3|3)_right_15b023591617b7f99063c796f466485f497b9648923e1837d792b37fa046309e
          (2/2|2)_right_173d0308c7347c9b848a26fc967e40f35f7a29024c6a764b1d99734bd9b5e312
          (3/3|3)_right_1ce1f629884e59e9e9aa707072fb1549ca488d5a283f9b2a49149d7f7a67fe79
          (2/2|2)_right_1e2c02325c3150fd7aef32b8650ce86ed7dd57b5160318cac38d9b24bd3992dd
          (2/2|2)_right_1ee5dc6ccc143d9d3bbd48adb22417e483a6d074a69975cb5819330a398659dd
          (2/2|2)_right_1f479a448deeb36325429be7a0cb17f506c99d281f10dd6f79e40f70ee5796a5
          (3/3|3)_right_1f6bee2ede264399e891211aeecf4d08380583eaaf396e933b957413a64a4452
          *(2/3|3)_right_21cfea16394e71af56ac62a6afa43aa7f73c3167e32ab2ebae4dfd29acc07538
          (2/2|2)_right_226f122b5676a5cdcda7d28b75bd7f8d27b7b61e76d3e36da269fa3c6ce12e76
          *(2/3|3)_right_30ab508e9d2405be78eff8cba5744fa51c4d8c3e20a2767e0ed6f7c7b03e756c
          (2/2|2)_right_3365a0f83b0aea481effbbe1c3f30da7bb6bbdbdad47db964a962206672c33bd
          (2/2|2)_right_3795811a41f49188eb5f30ea3f8da2c9f0ce31ca7fa1632fda71350ab66ec282
          (2/2|2)_right_420eb29bd4e35f2fbdf71436d2845dcab7e62b85064eda7f68903ced10ae9038
          (2/2|2)_right_429fa8b6b8e8a56688f25f5a47e912500d1be81e781132f3e466e4b9645ce5a3
          (2/2|2)_right_43ff1fc595ee46ac94dc5356b36096f3cf484b50f43b94885e46a70ca5426d5b
          (13/13|13)_right_45db132f83dd84c55c8fb76a6ef82d945ca73498a4a21f6550d3bfd87f5b499d
          (7/7|7)_right_4bb24ffce2c13f655251113465d6e509a4f81341b7b5e098115ae43ca47b1d6f
          (2/2|2)_right_57b0710b626b2c19f3ee8f41f13acf1f67083f09065c3614ebacd37c1bda9c5d
          (3/3|3)_right_5823649f5de84a15c9f16871b501e27c5553b07d7b19e4a4cf6362239493f088
          (2/2|4)_right_5fea5a2bdaf5c7669bde4554cd051a9bdf61bdbb9a8888ec1717fe4c633e3a5e
          (2/2|2)_right_602cea9bf4d2d662703c246422aac8903e014393cefc58ae597ef3f5a9344fb2
          (2/2|2)_right_61a7e198e40c1313882aefed010fb0b76f27eec4a4f8d9a9c86fb60ac8ddaa0d
          (3/3|3)_right_62f889a2973fc44bc6f7c4fc2d4ee55a44a33d01ec57c103fd6ce2a9d3202cba
          (2/2|2)_right_6508a7c4330477b881f4e2f3c004c97e228d2c274dbbdc56fedccd8a2acd4118
          (2/2|2)_right_67ebec08632ec20bf7ed8dd81db8be6834c6a540d0899d2f8e77a82d10c37f92
          (2/2|2)_right_6e8835d4ff1b71156d2707b5d650bf782632e05ebdb9c9b9cf9b0ad7f45768b5
          (2/2|2)_right_78ee3ddb9ff038b0bdce3218f294c82f54b008001a7523034f33abe47b1861aa
          (4/4|4)_right_817c074d4b43316315c9e5d1425c82b16b17e3af8d2c20deaeac6afac6755999
          (3/3|3)_right_81ca34179c3b4f05d8eec9de029dddf43c3b30e89cee57355f575b29c15b40d5
          (2/2|2)_right_861b36733adb6b21ffae068106404ef73882c97f9644d6b0ae5f7909ec8f2faa
          (4/4|4)_right_879313796b42e17c6ab30a14deaf73b7beaeaa291a0e053fef12572588f24ee9
          (3/3|3)_right_87bff3974b60118747137ddadb3ed8e0a74dceed25a0af8f3f1e770946f95292
          (2/2|2)_right_8839e1ea2d774e138b4126323d5876908983c933ef7999d873ce26ac8a9cdfa4
          (2/2|2)_right_88a468bdcd141ebc89df86e804a9252d91c2d4b45fa798fdfea6fed9634d2e67
          (13/13|13)_right_9308fb9729dfa5d61ab3f8ba9ad0f7ec360564ad0d53363f89b1223a31d5a066
          (2/2|2)_right_9ba590996b1991a5927d2c0cdbf4ca5c305b2193ff7dd4b0f7225f14a22983f5
          *(6/7|8)_right_a39935d63b17931459b6ffa967c5693a47975f8d6e7dda9e6f67bbe1ce289075
          (2/2|2)_right_a5443285061f5371f214730c3a285d19d433dd5fa448630d776a0d99f2bf5b2f
          (3/3|3)_right_a616f2c9061edcfb12c2ca22e96e6849e94784af0116f3a954a4cdf180678bb5
          (6/6|6)_right_a719fce70898515f1f20f8293e002a49d0ec80d0286280049c6f396ce74ce571
          (2/2|2)_right_bd6e94f4d0d5025f7fee1f5f60c1aac46a35a213d98458bb38338804e50a4ea3
          (2/2|2)_right_bde78cbe2b11d7ed6b93a56d981d350f1a9e97ce7e61f7bcf6d0ec776a7e9460
          (2/2|2)_right_c0e3b2a632e96d3469efb6010c53c789427aee526af6e61cf06ce393701be815
          (5/5|5)_right_c2476c832deffc887a5829397337bfe4acd39bbcf457bd4b9402995bc9bb483c
          (2/2|2)_right_c5979e0f656138067918b67af8934e124567efa4059d0f0e004bbc320a485b75
          (3/3|3)_right_c71e3c7060c36ebb59bb09359444ba1c140bae54de1a9bb4a1ac25c4d63005db
          (2/2|2)_right_c926e64c9838d58b1997a015ae2d052d95c195761f004ba3d8fecc3aa686afe9
          (2/2|2)_right_cb4c5d42bb161f5145fbdd4cb5b9cac5dfa035662e06d2aec966b5ea5482109d
          (3/3|3)_right_d2d1c141eb4e6f3d6a8e0698f435dbd6c8ade5285db2dbbc5466a287652583ec
          (5/5|5)_right_da0847ed979490f81ce92138b7e2378834167a33f2f4a06d321cce7d038e64ab
          (4/4|4)_right_da22fd85099f493d2bfe9edd67282b5267221bda88e60515897c4cd6eb397ef1
          (2/2|2)_right_e21cf5e864292dd495ae72bc0b9c2a43a978ebe5e1ecda13695af335d1b89ef6
          (2/2|2)_right_e4e126577bbbae45b353473d61e521b45dcd64a0ff904c8d43cd67a96e9e47f7
          (2/2|2)_right_e68e2fc2870008c216cca5557ec71c78f339851ce33cf18f0428806efa3d8b24
          (2/2|2)_right_e759bcdb0bd34ef0724640cdd1ce8ddbe922eebd1f15186aa22ceac11debdd77
          (7/7|7)_right_f300820eec3b0127c500932db6c7437a3665183f063c4fcff133dc23c82bfc2a
          (3/3|3)_right_f4ce04fc56e4a1e6d983496469b39567bf302fd8f74408480f1f12b770607a44
          (2/2|2)_right_f5d43950541487fc364a6e9321acc0334546fd2066b2b4ddf9d624d66fabc481
          (2/2|2)_right_f8121e7e486f37a9e5025aa264dbe8d8f1a39ca657d56b522f0a6c3f57ce22c8
          (4/4|4)_right_f92cff2a6e3f061b9a7abf5cd6db6b034b852c597fac9e2dc9ed17f6ec8e269c
          (3/3|3)_right_fa26570b633442ff532987aaa15d57a11e1df7a5821cde686a07f9f1ed29d4fb
          (2/2|2)_right_fdcfd399989110d49e38d9cb49818a7ee1a89cce61c02aab6dbb6b8f97305bd8
        ];

        my @clusters_to_use = (
            @non_physiologic_ig_clusters, @physiologic_ig_clusters, @off_targets
        );

        @clusters_to_use = @non_physiologic_ig_clusters;
        @clusters_to_use = @physiologic_ig_clusters;
        @clusters_to_use = @off_targets;

        my %debug;

#        my $selected_hts = ['hotspot101','hotspot104','hotspot109','hotspot11','hotspot118','hotspot120','hotspot129','hotspot134','hotspot148','hotspot149','hotspot150','hotspot151','hotspot154','hotspot155','hotspot156','hotspot157','hotspot158','hotspot159','hotspot160','hotspot161','hotspot163','hotspot175','hotspot177','hotspot181','hotspot190','hotspot199','hotspot208','hotspot27','hotspot3','hotspot30','hotspot36','hotspot41','hotspot43','hotspot44','hotspot49','hotspot50','hotspot52','hotspot58','hotspot71','hotspot73','hotspot77','hotspot82','hotspot86','hotspot9','hotspot91','hotspot99'];

        
 #       my $igs = ['hotspot149','hotspot150','hotspot151','hotspot154','hotspot155','hotspot156','hotspot157','hotspot158','hotspot159','hotspot160','hotspot161','hotspot163','hotspot36','hotspot148','hotspot162','hotspot152', 'hotspot153'];
  #      my $off_targets = ['hotspot91','hotspot129','hotspot27','hotspot43','hotspot30','hotspot58','hotspot118','hotspot52','hotspot41','hotspot175','hotspot49','hotspot120','hotspot109','hotspot44','hotspot99','hotspot82','hotspot104','hotspot86','hotspot77','hotspot71','hotspot50','hotspot177','hotspot190','hotspot9','hotspot208','hotspot3','hotspot199','hotspot181','hotspot101','hotspot11','hotspot73','hotspot134'];

        my $hotspots_rs = $schema->resultset('Hotspot')->search(
            {   'me.library_id' => $lib_id,
                # Comment this line to have all data
                #'hotspot_dummy_name' => { 'IN' => $off_targets },
                # Filter not reliable breakpoints
                #breakpoint_name => { "-not_like" =>  [ '-OR' => ('#%','%1/%|%') ] },
                 breakpoint_name => { "IN" => \@clusters_to_use   },
                
            },
            {   prefetch => [
                    {   'hotspot_has_shears' => {
                            'shear' => [
#                                {   'shear_has_seqs' => {
#                                        'seq' =>
#                                            [ 'target_sequence', 'bait_sequence', 'microhomology_bait_alignments' ]
#                                    },
#                                },
                                { 'shear_has_breakpoints' => 'breakpoint' },
                                ['microhomologies_defined','insertions_defined',],

                            ]
                        }
                    }
                ],
            }
        );

        say $hotspots_rs->count;
        my $total_seq           = 0;
        my $total_breakpoint    = 0;
        my $total_microhomology = 0;
        #exit;
        while ( my $ht = $hotspots_rs->next ) {

            my $shears             = $ht->shears;
            my $hotspot_dummy_name = $ht->hotspot_dummy_name;

            say $ht->hotspot_dummy_name . " ("
                . $shears->count . ")" . " ["
                . $ht->hotspot_chr . ":"
                . $ht->hotspot_start . "-"
                . $ht->hotspot_end . "]";

            # Get hotspot fastq sequence

            while ( my $shear = $shears->next ) {
                my $seqs       = $shear->seqs;
                my $breakpoint = $shear->breakpoints->first;
                
                say "\t" . $shear->shear_name . " (" . $seqs->count . ")";
               
                # Only check if there is a breakpoint (this could be removed
                # latter)
                if ($breakpoint) {                    
                    say "\t" . $breakpoint->breakpoint_name;
                    # removing not reliable breakpoints
                    next if $breakpoint->breakpoint_name =~ /#|\(1\/\d+\|/;
                    my %breakpoint_microhomology;
                    my %breakpoint_insertion;
                    my $breakpoint_blunt;
                    my %seq_ids;

                    while ( my $seq = $seqs->next ) {
                        say "\t\t" . $seq->read_name;
                        my $target = $seq->target_sequence;
                        my $bait   = $seq->bait_sequence;
                        my $microhomology_bait_alignment = $seq->microhomology_bait_alignments->first;
                        
                        # if there is information in database about the
                        # microhomology
                        if ($microhomology_bait_alignment) {

                            say "\t\t","BAIT:";
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_query_start, "-",
                                $microhomology_bait_alignment->microhomology_bait_query_end;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_reference_sequence;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_match_string;
                            say "\t\t\t",$microhomology_bait_alignment->microhomology_bait_query_sequence;
                            
                            # If besides bait target was mapped too
                            if ( $microhomology_bait_alignment->microhomology_target_query_sequence ) {
                                    say "\t\t","TARGET:";
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_query_start, "-",
                                        $microhomology_bait_alignment->microhomology_target_query_end;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_reference_sequence;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_match_string;
                                    say "\t\t\t",$microhomology_bait_alignment->microhomology_target_query_sequence;

                                if ( $microhomology_bait_alignment->microhomology_size ) {
                                    $breakpoint_microhomology{$microhomology_bait_alignment->microhomology_size}++;
                                    push @{$seq_ids{microhomology}}, $seq->id;
                                }
                                elsif ($microhomology_bait_alignment->microhomology_insertion_size) {
                                    $breakpoint_insertion{$microhomology_bait_alignment->microhomology_insertion_size}++;
                                    push @{$seq_ids{insertion}}, $seq->id;
                                }
                                else{
                                    $breakpoint_blunt++;
                                }
                            }
                            say "";
                            say "";
                        }
                        $total_seq++;
                    }

                    my %final_type;
                    my %final_number;
                   
                    say "Insertion:";
                    foreach my $size (sort { ($breakpoint_insertion{$b} <=> $breakpoint_insertion{$a} ) || ($b <=> $a) } keys %breakpoint_insertion){
                        say "\t$size: $breakpoint_insertion{$size}";
                        unless ($final_type{insertion}){
                            $final_type{insertion}{reads} = $breakpoint_insertion{$size};
                            $final_type{insertion}{size} = $size;
                            $final_number{$breakpoint_insertion{$size}} = 'insertion';
                        }
                    }
 
                    say "Microhomology";                    
                    
                    foreach my $size (sort { ($breakpoint_microhomology{$b} <=> $breakpoint_microhomology{$a} ) || ($b <=> $a) } keys %breakpoint_microhomology){
                        say "\t$size: $breakpoint_microhomology{$size}";
                        unless ($final_type{microhomology}){
                            $final_type{microhomology}{reads} = $breakpoint_microhomology{$size};
                            $final_type{microhomology}{size} = $size;
                            $final_number{$breakpoint_microhomology{$size}} = 'microhomology';
                        }
                    }
                    
                    if ($breakpoint_blunt) {
                        say "Blunt: $breakpoint_blunt";
                        $final_type{blunt}{reads} = $breakpoint_blunt;
                        $final_number{$breakpoint_blunt} = 'blunt';
                        $final_type{blunt}{size} = 0;
                    }

                   
                    if (scalar keys %final_type > 1){
                        my $n_reads = max(keys %final_number);
                        my $type = $final_number{$n_reads};
                        %final_type = (
                            $type => $final_type{$type}
                        );
                    }

                    foreach my $type (keys %final_type) {
                        say "$type, size ($final_type{$type}{size}), supported by $final_type{$type}{reads} reads!";
                        open( my $out, '>>', "/tmp/microhomology.bed" )
                            || die "Cannot open/write file " . "/tmp/microhomology.bed" . "!";
                        if ($type =~ /micro/){
                            my ($start,$end);
                            if ($breakpoint->breakpoint_strand eq '+'){
                                $start = $breakpoint->breakpoint_end;
                                $end = $breakpoint->breakpoint_end + $final_type{$type}{size};
                            }
                            else {
                                $start = $breakpoint->breakpoint_start - $final_type{$type}{size};
                                $end = $breakpoint->breakpoint_start;
                            }

                            say $out join "\t",($breakpoint->breakpoint_chr, $start, $end, $breakpoint->breakpoint_name."!".$ht->hotspot_dummy_name , $final_type{$type}{reads}, $breakpoint->breakpoint_strand );

                            # Add to database
#                            $schema->resultset('MicrohomologyDefined')->create(
                                #{   shear_id             => $shear->id,
                                    #hotspot_id           => $ht->id,
                                    #microhomology_size   => $final_type{$type}{size},
                                    #microhomology_chr    => $breakpoint->breakpoint_chr,
                                    #microhomology_start  => $start,
                                    #microhomology_end    => $end,
                                    #microhomology_strand => $breakpoint->breakpoint_strand,
                                    #microhomology_color  => "153,0,76"
                                #}
                            #);

                            ## Add to database:
                            #foreach my $id ( @{ $seq_ids{microhomology} } ) {
                                #$schema->resultset('MicrohomologyDefinedHasSeq')->create(
                                    #{   shear_id   => $shear->id,
                                        #hotspot_id => $ht->id,
                                        #seq_id     => $id,
                                    #}
                                #);
                            #}
                        }
                        close( $out );

                        open( $out, '>>', "/tmp/insertions.bed" )
                            || die "Cannot open/write file " . "/tmp/insertions.bed" . "!";
                        if ( $type =~ /insert/ ) {
                            my ( $start, $end );
                            $start = $breakpoint->breakpoint_start;
                            $end   = $breakpoint->breakpoint_end;
                            say $out join "\t",
                                (
                                $breakpoint->breakpoint_chr,
                                $start, $end,
                                "insertion($final_type{$type}{size})_".$breakpoint->breakpoint_name."!".$ht->hotspot_dummy_name,
                                $final_type{$type}{reads},
                                $breakpoint->breakpoint_strand
                                );

                        }
                        close( $out );
                        
                        open( $out, '>>', "/tmp/blunt.bed" )
                            || die "Cannot open/write file " . "/tmp/blunt.bed" . "!";
                        if ( $type =~ /blunt/ ) {
                            my ( $start, $end );
                            $start = $breakpoint->breakpoint_start;
                            $end   = $breakpoint->breakpoint_end;
                            say $out join "\t",
                                (
                                $breakpoint->breakpoint_chr,
                                $start, $end,
                                "blunt($final_type{$type}{size})_".$breakpoint->breakpoint_name."!".$ht->hotspot_dummy_name,
                                $final_type{$type}{reads},
                                $breakpoint->breakpoint_strand
                                );

                        }
                        close( $out );

                            $debug{$breakpoint->breakpoint_name} = 1;
                       
                    }

                 }
            }
        }
        
        foreach my $i (@clusters_to_use) {
            say $i unless $debug{$i};
        }

        say $total_seq;
    }
}





class Main {
    import MyApp::Populate;
    MyApp::Populate->new_with_command->run();
}

