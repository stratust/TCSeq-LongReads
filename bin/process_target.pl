#!/usr/bin/env perl
use Moose;
use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
BEGIN { our $Log_Level = 'info' }
 
class MyApp is dirty {
    use MooseX::App qw(Color);
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
}


class MyApp::ProcessTarget {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::DB::Sam;
    use Data::Printer;
    use Progress::Any;
    use Progress::Any::Output;
    use Number::Format qw(format_number);
    use Digest::SHA qw(sha256_hex);
    
    Progress::Any::Output->set('TermProgressBarColor');


    command_short_description q[Process a BAM file to generate cluster of reads];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(i)],
        required      => 1,
        documentation => q[Target alignment in bam BAM format!],
    );

    has 'min_size' => (
        is            => 'rw',
        isa           => 'Int',
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(m)],
        required      => 1,
        default      => '3',
        documentation => q[Mininum size to start the alignment],
    );

    has 'min_match_size' => (
        is            => 'rw',
        isa           => 'Int',
        traits        => ['AppOption'],
        cmd_type      => 'option',
        required      => 1,
        default      => '36',
        documentation => q[ Mininum match size of the alignment to be accepted ],
    );

    has 'min_qual' => (
        is            => 'rw',
        isa           => 'Int',
        traits        => ['AppOption'],
        cmd_type      => 'option',
        required      => 1,
        default      => '20',
        documentation => q[ Mininum quality of the alignment to be accepted ],
    );

    method run {
        my $bam_entries = 0;
        my $bam_unmapped = 0;

        my $bame         = Bio::DB::Bam->open( $self->input_file );
        my $bam_out = $self->input_file;
        $bam_out =~ s/\.bam$/\.filtered\.bam/;
        my $bamo         = Bio::DB::Bam->open( $bam_out,'w' );
        my $header       = $bame->header;
        my $status_Code =  $bamo->header_write($header);
        my $target_count = $header->n_targets;
        my $target_names = $header->target_name;
        

        $self->log->debug( 'target bam file: ' . $self->input_file );
        
        $self->log->info('Getting bam size');
        my $cmd = "samtools view ". $self->input_file ." | wc -l";
        my $bam_size = qx/$cmd/;
        $self->log->info('Parsing bam and creating hash');
        my $progress = Progress::Any->get_indicator(
                     task => "Read_bam", target=> $bam_size
        );
        
        my %targets;
        # Optimize perl hash given size of hash keys
        keys(%targets) = $bam_size;
        
        while ( my $align = $bame->read1 ) {
            my ( $qname, $query_start, $query_end, $query_dna );
            $bam_entries++;
            $progress->update( message => "Entry: " . format_number($bam_entries) );
            $qname = $align->qname;
            $targets{$qname} = [] unless $targets{$qname};
            if ( $align->unmapped ) {
                $bam_unmapped++;
                next;
            }
            else {
               my $strand = '+';
                $strand = '-' if $align->strand == -1;

               next if $align->qual < $self->min_qual  || $align->length < $self->min_match_size;

                # Strand matters
                # Postitive strand
                my $query_start;
                if ( $align->strand == 1 ) {
                    $query_start = $align->query->start;
                }
                # Negative strand
                else {
                    $query_start = ( length( $align->query->dna ) - $align->query->end ) + 1;
                }
                
                next if $query_start >= $self->min_size;

                my %h = (
                    chr    => $target_names->[ $align->tid ],
                    start  => $align->pos,
                    end    => $align->calend,
                    strand => $strand,
                    #length => $align->length,
                    qstart => $query_start,
                    aln => $align
                );
                #p %h;
                push @{ $targets{$qname} }, \%h;
            }

        }
        
        $progress->finish;

        my %info;
        my $reads = 0;
        my $bait_chr=0;
        my $same_chr=0;
        my $one_bait=0;
        my $diff_chr=0;

        my %bed;
        my %shear_read_names;
        $self->log->info('Filtering Hash');
        foreach my $k (keys %targets) {
            $info{scalar @{$targets{$k}}}++;
            $reads++;
            if ( scalar @{ $targets{$k} } == 1 ) {
                my $h = $targets{$k}->[0];
                my $primer='left';
                $primer = 'right' if $k =~ /right/;
                if ( $h->{strand} eq '+' ) {                    
                    my $key = join "|",
                      (
                        $h->{chr}, $h->{start}, $h->{start} + 1,$primer,
                        $h->{strand}
                      );
                      $bed{$key}++;
                      push @{ $shear_read_names{$key} }, $k;
                }
                else {
                    my $key = join "|",
                      ( $h->{chr}, $h->{end} - 1, $h->{end}, $primer ,$h->{strand} );
                    $bed{$key}++;
                    push @{ $shear_read_names{$key} }, $k;
                }
                
                my $bytes = $bamo->write1($h->{aln});
            }
            
            if ( scalar @{ $targets{$k} } == 2 ) {
                my $h1 = $targets{$k}->[0];
                my $h2 = $targets{$k}->[1];
                if ( $h1->{chr} eq 'chr15' && $h2->{chr} eq 'chr15' ) {
                    $bait_chr++;
                    say "$h1->{qstart} | $h2->{qstart}";
                }
                elsif ( $h1->{chr} eq 'chr15' || $h2->{chr} eq 'chr15' ) {
                    $one_bait++;
                    # Get this split
                }
                elsif ( $h1->{chr} eq $h2->{chr} ) {
                    $same_chr++;
                }
                else{
                    $diff_chr++;
                }

            }
        }

        my $outfile = $self->input_file;

        $outfile =~ s/\.bam/\.bed/g;
        open( my $out, '>', $outfile )
            || die "Cannot open/write file " . $outfile . "!";

        my $indexfile = $self->input_file;    
        $indexfile =~ s/\.bam/\.shears_index/g;
        open( my $out_index, '>', $indexfile )
            || die "Cannot open/write file " . $indexfile . "!";


        my %primer = (right => 1, left => 1);
        my %color = (right => '255,127,0', left => '77,175,74');
            
        my $track="track name= visibility=squish itemRgb=On";
        my $transloc = length(scalar keys %bed);
        foreach my $key (sort {$a cmp $b} keys %bed) {
            my @F = split /\|/, $key;
            
            my $sorted_read_names_string = join( ',', sort { $a cmp $b } @{ $shear_read_names{$key} } );
            my $sha256_id = sha256_hex($sorted_read_names_string);

            #my $shear_id = $F[3] . '_' . sprintf( "%0" . $transloc . "d", $primer{ $F[3] }++ );
            
            my $shear_id = $F[3] . '_' . $sha256_id;

            say $out join "\t",
              (
                @F[ 0, 1, 2 ],
                $shear_id,
                $bed{$key},
                $F[4],
                @F[ 1, 2 ],
                $color{ $F[3] }
              );

            say $out_index $shear_id .
                "\t" .
                $bed{$key} .
                "\t" . 
                $sorted_read_names_string;

        } 
        close( $out );
        close( $out_index );
        
        p %info;
        say "bam_entries: $bam_entries";
        say "unmapped: $bam_unmapped";
        say "reads: $reads";
        say "-------";
        say "both in bait: $bait_chr";
        say "one in bait: $one_bait";
        say "same chr: $same_chr";
        say "diff chr: $diff_chr";

        $self->log->debug( 'bam file: ' . $self->input_file );
    }
}


class MyApp::FixBed {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
    use Data::Printer;
    use File::Basename;
    
    command_short_description q[Fix a transloc bed file];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'i',
        required      => 1,
        must_exist    => 1,
        coerce => 1,
        documentation => 'Transloc BED file',
    );

    option 'nmin' => (
        is            => 'rw',
        isa           => 'Int',
        required      => 1,
        default       => 2,
        documentation => q[Mininum reads in the same target],
    );

    option 'track_name' => (
        is            => 'rw',
        isa           => 'Str',
        required      => 0,
        documentation => q["Track name to be used."],
    );

    method run {
        my $in = Bio::Moose::BedIO->new(file => $self->input_file->stringify);

        my %color = (right => '255,127,0', left => '77,175,74');
        my $file = basename($self->input_file);
        $file = $self->track_name if $self->track_name;
        say "track name='$file' description='$file' visibility='squish' itemRgb='On'";
        while (my $f = $in->next_feature) {
            next if $f->score < $self->nmin;
            my $primer = 'right';
            $primer = 'left' if $f->name =~ /left/;
            $f->itemRgb($color{$primer});
            $f->thickStart($f->chromStart);
            $f->thickEnd($f->chromEnd);

            $in->write($f);
        }
    }
}


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


class MyApp::RetrieveReads {
    extends 'MyApp'; # inherit log
    with 'MyApp::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
    use Bio::SeqIO;
    use Data::Printer;
    use File::Basename;
    
    command_short_description q[Retrieve reads given index files for shears and hotspots];



    has_file 'target_fasta_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 't',
        required      => 0,
        must_exist    => 1,
        documentation => 'Target FASTA file',
    );

    has_file 'bait_fasta_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'b',
        required      => 0,
        must_exist    => 1,
        documentation => 'Bait FASTA file',
    );

    has_file 'output_bait_fasta_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'ob',
        lazy          => 1,
        builder       => '_build_bait_output_file',
        documentation => 'Output FASTA file with all bait sequences',
    );

    has_file 'output_target_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'ot',
        lazy          => 1,
        builder       => '_build_target_output_file',
        documentation => 'Output FASTA file with all target sequences',
    );

    has_directory 'output_dir' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'd',
        required      => 1,
        must_exist    => 1,
        default => '.',
        documentation => 'Output directory',
    );
    

    method _build_bait_output_file {
        my $outfile = undef;
        if ( $self->bait_fasta_file ) {
            my ( $name, $path, $suffix ) =
              fileparse( $self->bait_fasta_file, [ '.fasta', '.fa' ] );
            if ( $self->output_dir ) {
                $outfile = $self->output_dir . "/hotspot_selected_" . $name;
            }
            else {
                $outfile = $path . "hotspot_selected_" . $name;
            }
        }
        return $outfile;
    }

    method _build_target_output_file  {
        my $outfile = undef;
        if ( $self->target_fasta_file ) {
            my ( $name, $path, $suffix ) =
              fileparse( $self->target_fasta_file, [ '.fasta', '.fa' ] );
            if ( $self->output_dir ) {
                $outfile = $self->output_dir . "/hotspot_selected_" . $name;
            }
            else {
                $outfile = $path . "hotspot_selected_" . $name;
            }
        }
        return $outfile;
    }


    method run {
        my $reads = $self->get_read_names_from_hotspots;

        $self->log->info("Selecting bait reads");
        if ( $self->bait_fasta_file ) {
            my $in = Bio::SeqIO->new(
                -file   => $self->bait_fasta_file,
                -format => 'fasta'
            );

            my $out = Bio::SeqIO->new(
                -file   => '>' . $self->output_bait_fasta_file,
                -format => 'fasta'
            );

            while ( my $seq = $in->next_seq ) {
                if ( $reads->{ $seq->id } ) {
                    my $aux = $reads->{ $seq->id };
                    $seq->id(
                        $seq->id . "|$aux->{shear_id}|$aux->{hotspot_id}" );
                    $out->write_seq($seq);
                }
            }
        }

        $self->log->info("Selecting target reads");
        if ( $self->target_fasta_file ) {
            my $in = Bio::SeqIO->new(
                -file   => $self->target_fasta_file,
                -format => 'fasta'
            );

            my $out = Bio::SeqIO->new(
                -file   => '>' . $self->output_target_file,
                -format => 'fasta'
            );

            while ( my $seq = $in->next_seq ) {
                if ( $reads->{ $seq->id } ) {
                    my $aux = $reads->{ $seq->id };
                    $seq->id(
                        $seq->id . "|$aux->{shear_id}|$aux->{hotspot_id}" );
                    $out->write_seq($seq);
                }
            }
        }
    }
}


class MyApp::FilterFragmentAlignments {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::DB::Sam;
    use Bio::SeqIO;
    use Data::Printer;
    use Progress::Any;
    use Progress::Any::Output;
    use Number::Format qw(format_number);
    use Moose::Util::TypeConstraints;
    
    Progress::Any::Output->set('TermProgressBarColor');


    command_short_description q[Process a BAM file to generate cluster of reads];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(i)],
        required      => 1,
        documentation => q[Bait/Target alignment against cMyc fragment in bam BAM format!],
    );

    has_file 'output_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(o)],
        required      => 1,
        documentation => q[Output file name],
    );

    has 'min_seq_size' => (
        is            => 'rw',
        isa           => 'Int',
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(m)],
        required      => 1,
        default      => '29',
        documentation => q[Mininum accepted sequence size to be included in the fasta file],
    );
    
    has 'sequence_type' => (
        is            => 'rw',
        isa           => subtype( as 'Str', where {/^target$|^bait$/} ),
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(s)],
        required      => 1,
        default      => 'bait',
        documentation => q[Sequence type (target or bait) in order to get softclipped sequences. (bait: 3' ends, targe: 5' ends)],
    );
 
    method get_softclipped_sequence ( Bio::DB::Bam::Alignment $align, Str $position where qr{before_match|after_match} ) {

        my $cigar = $align->cigar_array;
        my $tdna  = $align->query->dna;

        # Always work sequence in 5'to 3'
        if ( $align->strand == -1 ) {
            @{$cigar} = reverse @{$cigar};
            $tdna = reverse $tdna;
            $tdna =~ tr/actgACTG/tgacTGAC/;
        }

        my @ops;
        my $regex;
        for my $event (@$cigar) {
            my ( $op, $count ) = @$event;
            push @ops, $op;
            $regex .= '(\w{' . $count . '})';
        }

        my ( $before, $after, $match );
        my $i = 0;

        foreach my $op (@ops) {
            $before = $i if ( $op eq 'S' && !defined $match );
            $match = 1 if $op eq 'M';
            $after = $i if ( $op eq 'S' && $match );
            $i++;
        }

        my @seqs = ( $tdna =~ m/$regex/g );
        my $soft_seq;

        if ( $position eq 'before_match' ) {
            $soft_seq = $seqs[$before] if defined $before;
        }
        else {
            $soft_seq = $seqs[$after] if defined $after;
        }

        return $soft_seq;
    }

    method run {
        my $bam_entries = 0;
        my $bam_unmapped = 0;
        my $bam_short_softclipped = 0;

        my $bame         = Bio::DB::Bam->open( $self->input_file );
        my $bam_out = $self->input_file;
        $bam_out =~ s/\.bam$/\.filtered\.bam/;
        my $bamo         = Bio::DB::Bam->open( $bam_out,'w' );
        my $header       = $bame->header;
        my $status_Code =  $bamo->header_write($header);
        my $target_count = $header->n_targets;
        my $target_names = $header->target_name;

        $self->log->debug( 'target bam file: ' . $self->input_file );
        
        $self->log->info('Getting bam size');
        my $cmd = "samtools view ". $self->input_file ." | wc -l";
        my $bam_size = qx/$cmd/;
        $self->log->info('Parsing bam and creating hash');
        my $progress = Progress::Any->get_indicator(
                     task => "Read_bam", target=> $bam_size
        );
        
        my %targets;
        # Optimize perl hash given size of hash keys
        keys(%targets) = $bam_size;

        while ( my $align = $bame->read1) {
            my ( $qname, $query_start, $query_end, $query_dna );
            
            $bam_entries++;
            
            $progress->update( message => "Entry: " . format_number($bam_entries) );
            
            $qname = $align->qname;
            $targets{$qname} = [] unless $targets{$qname};
            
            if ( $align->unmapped ) {
                $bam_unmapped++;
                if ($self->sequence_type eq 'bait'){
                    $self->log->error("Unmapped read found. You shouldn't have unmapped reads in this file. Check your bam file:". $qname);
                    die;
                }
            }
            else {
               my $strand = '+';
               $strand = '-' if $align->strand == -1;

               my $position;

               if ($self->sequence_type eq 'bait'){
                   $position = 'after_match';
               }
               elsif ($self->sequence_type eq 'target'){
                   $position = 'before_match';   
               }

               my $clipped_seq = $self->get_softclipped_sequence($align, $position);

               if (!defined $clipped_seq || length($clipped_seq) < $self->min_seq_size ){
                    $bam_short_softclipped++;
                    next;
               }

               my %h = (
                    chr    => $target_names->[ $align->tid ],
                    start  => $align->pos,
                    end    => $align->calend,
                    strand => $strand,
                    qstart => $query_start,
                    clipped_seq => $clipped_seq,
                    aln => $align
                );
                push @{ $targets{$qname} }, \%h;
            }

        }
        
        $progress->finish;

        my %info;
        my $reads = 0;

        my %bed;
        my %shear_read_names;
        
        $self->log->info('Filtering Hash');

        my $out = Bio::SeqIO->new(-file => ">".$self->output_file, -format => 'fasta');

        foreach my $k (keys %targets) {
            $info{scalar @{$targets{$k}}}++;
            $reads++;
            if ( scalar @{ $targets{$k} } == 1 ) {
                # Get BAM alignment
                my $align = $targets{$k}[0]->{aln};
                # Get clipped sequence
                my $clipped = $targets{$k}[0]->{clipped_seq};
                # Get Bio::SeqI object representing the original sequence
                my $seq = $align->query->seq;
                # Replace original sequence with clipped sequence
                $seq->seq($clipped);
                # Write object into FASTA file
                $out->write_seq($seq);
            }
            if ( scalar @{ $targets{$k} } > 1 ) {
                 $self->log->error("Split in sequence shouldn't be reported. Check your bam file:". $k);
            }
        }

        p %info;
        say "bam_entries: $bam_entries";
        say "unmapped: $bam_unmapped";
        say "short softclipped seqs: $bam_short_softclipped";
        say "reads: $reads";

        $self->log->debug( 'bam file: ' . $self->input_file );
    }
}


class MyApp::GetBreakPoint {
    extends 'MyApp'; # inherit log
    with 'MyApp::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
    use Bio::SeqIO;
    use Data::Printer;
    use File::Basename;
    use Progress::Any;
    use Progress::Any::Output;
    use Number::Format qw(format_number);

    command_short_description q[];
    
    has_file 'target_bam_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 't',
        required      => 0,
        must_exist    => 1,
        documentation => 'Target BAM file',
    );

    has_file 'restriction_bam_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'r',
        required      => 1,
        must_exist    => 1,
        documentation => 'Bait restriction  BAM file',
    );


    has_file 'bait_bam_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'b',
        required      => 0,
        must_exist    => 1,
        documentation => 'Bait BAM file',
    );

    has_file 'shear_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 's',
        required      => 1,
        must_exist    => 1,
        documentation => 'Shear file',
    );

    has_file 'output_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'o',
        lazy          => 1,
        builder       => '_build_output_file',
        documentation => 'Output BED file',
    );

    has 'shears' => (
        is            => 'rw',
        isa           => 'HashRef',
        lazy          => 1,
        builder       => 'parse_shear_file',
        documentation => 'Shear index hash',
    );
    

    method parse_shear_file {
        my %index;
        my $in = Bio::Moose::BedIO->new(file => $self->shear_file->stringify);
        while (my $feat = $in->next_feature){
            $index{$feat->name} = $feat;
        } 
        return \%index;
    }

    method _build_output_file {
        my $filename = $self->shear_file;
        $filename.= ".breakpoints";
        return $filename;
    }


    method parse_bam_file($bam_file, Str $seq_type where {$_ =~ /^bait$|^target$|^restriction$/}, HashRef $hash) {
        my $bam_entries = 0;
        my $bam_unmapped = 0;

        my $bame         = Bio::DB::Bam->open( $bam_file );
        my $header       = $bame->header;
        my $target_count = $header->n_targets;
        my $target_names = $header->target_name;

        $self->log->debug( 'bam file: ' . $bam_file );
        
        $self->log->info('Getting bam size');
        my $cmd = "samtools view ". $bam_file ." | wc -l";
        my $bam_size = qx/$cmd/;
        
        $self->log->info('Parsing bam and creating hash');
        my $progress = Progress::Any->get_indicator(
                     task => "Read_bam", target=> $bam_size
        );
        
        my %targets;
        # Optimize perl hash given size of hash keys
        keys(%targets) = $bam_size;

        while ( my $align = $bame->read1) {
            my ( $qname, $query_start, $query_end, $query_dna );
            
            $bam_entries++;
            
            $progress->update( message => "Entry: " . format_number($bam_entries) );
            
            $qname = $align->qname;
            $targets{$qname} = [] unless $targets{$qname};
            
            if ( $align->unmapped ) {
                $bam_unmapped++;
            }
            else {
               my $strand = '+';
               $strand = '-' if $align->strand == -1;

               next if $align->qual < 20  || $align->length < 36;

               my $start = $align->pos;
               my $end = $align->calend;
               my %h = (
                    chr    => $target_names->[ $align->tid ],
                    start  => $start,
                    end    => $end,
                    strand => $strand,
                    qstart => $query_start,
                    aln => $align
                );
                push @{ $targets{$qname} }, \%h;
            }

        }
        
        $progress->finish;

        my %info;
        my $reads = 0;

        my %bed;
        my %shear_read_names;
        
        $self->log->info('Filtering Hash');

        foreach my $k ( keys %targets ) {
            $info{ scalar @{ $targets{$k} } }++;
            $reads++;

            # Annotating restriction
            if ( $seq_type =~ /restriction/i ) {

                # Get before and/or after restriction site info
                my %info;
                foreach my $aln ( @{ $targets{$k} } ) {
                    $info{$aln->{chr}} = 1;
                }

                my ( $read, $shear_id, $hotspot_id ) = split /\|/, $k;
                my $aux = $hash->{$hotspot_id}{$shear_id}{$read};
                if ( $aux) {
                    if ( $aux == 1 ) {
                        $hash->{$hotspot_id}{$shear_id}{$read} = { $seq_type => \%info };
                    }
                    else {
                        $hash->{$hotspot_id}{$shear_id}{$read}{$seq_type} = \%info;
                    }
                }
                else {
                    $self->log->error( "Could not find hotspot, shear or read name for:" . $k . 'in restriction bam!' );
                }
            }
            else {
                # Annotating breakpoints
                if ( scalar @{ $targets{$k} } == 1 ) {

                    # Get BAM alignment
                    my $align = $targets{$k}[0]->{aln};
                    my $this  = $targets{$k}[0];

                    #my $pos = $this->{chr}.':'.$this->{start}.'-'.$this->{end}."\t".$this->{strand}.":".$align->qual;
                    my $pos = $this;
                    my ( $read, $shear_id, $hotspot_id ) = split /\|/, $k;
                    my $aux = $hash->{$hotspot_id}{$shear_id}{$read};
                    if ($aux) {
                        if ( $aux == 1 ) {
                            $hash->{$hotspot_id}{$shear_id}{$read} =
                              { $seq_type => $pos };
                        }
                        else {
                            $hash->{$hotspot_id}{$shear_id}{$read}{$seq_type} =
                              $pos;
                        }
                    }
                    else {
                        $self->log->error(
                            "Could not find hotspot, shear or read name for:"
                              . $k );
                    }
                }
                elsif ( scalar @{ $targets{$k} } > 1 ) {
                    $self->log->error( "Split in sequence shouldn't be reported. Check your bam file:" . $k );
                }
            }
        }

        p %info;
        say "bam_entries: $bam_entries";
        say "unmapped: $bam_unmapped";
        say "reads: $reads";

        return $hash;
    }

    method run  {
        my $hash = $self->get_hotspots_shear_reads;
        $hash = $self->parse_bam_file( $self->bait_bam_file,   "bait",   $hash );
        $hash = $self->parse_bam_file( $self->target_bam_file, "target", $hash );
        $hash = $self->parse_bam_file( $self->restriction_bam_file, "restriction", $hash );

        #p $hash;
        #exit;

        my %breakpoint_starts;
        my %breakpoint_positions;

        my ( $total_shear_count, $total_hotspot_count, $total_read_count ) = 0 x 3;

        foreach my $hotspot_id ( sort { $a cmp $b } keys %{$hash} ) {
            my $ht              = $hash->{$hotspot_id};
            my $breakpoint_read = 0;
            $total_hotspot_count++;    # count hotspots

            foreach my $shear_id ( sort { $a cmp $b } keys %{$ht} ) {
                my $shear = $ht->{$shear_id};
                $total_shear_count++;    # count shears
                
                my %starts; # keep all breakpoint starts for this shear
                
                foreach my $read_name ( sort { $a cmp $b } keys %{$shear} ) {
                    $total_read_count++;    # count reads
                    my $read = $shear->{$read_name};

                    if ( ref $read ) {
                        $breakpoint_read++;

                        # Check if there is bait information
                        my $bait   = $read->{bait};
                        my $target = $read->{target};
                        
                        # Chech if there is restriction information
                        my $restriction = $read->{restriction};

                        if ( ref $restriction ){
                            if ($restriction->{left} && $restriction->{right}){
                                $self->log->warn("Crossing breakpoint ". $read_name);
                                next;
                            }
                            elsif ($restriction->{left} && $read_name =~ /right/i) {
                                $self->log->warn("Wrong primer ". $read_name);
                                next;
                            }
                            elsif ($restriction->{right} && $read_name =~ /left/i) {
                                $self->log->warn("Wrong primer ". $read_name);
                                next;
                            }
 
                        }

                        next unless (ref $bait || ref $target );

                        # check breakpoint for bait and target
                        my $position = $self->define_breakpoint(shear_id => $shear_id, bait => $bait, target => $target );
                        if ($position ){
                            $starts{$position->{start}}++;
                            push @{$breakpoint_positions{$shear_id}{$position->{start}} },$position;
                        }
                    }
                    else {
                        # no read from bait or target to give breakpoint for
                    }
                }
                $breakpoint_starts{$shear_id} = \%starts;
            }
            $self->log->info("No reads for this hotspot: ". $hotspot_id) unless $breakpoint_read;
        }

        # Create BED file
        my @features;
        foreach my $shear_id ( sort { $a cmp $b } keys %breakpoint_starts ) {
            my $real_shear = $self->shears->{$shear_id};

            # add field for Bed12
            $real_shear->blockCount(1);
            $real_shear->blockSizes(1);
            $real_shear->blockStarts(0);

            my $shear      = $breakpoint_starts{$shear_id};
            if (%{ $shear }) {
                my @starts = sort { $shear->{$b} <=> $shear->{$a} } keys %{$shear};
                my @counts = values %{$shear};
                my $total_reads_bp = 0;
                $total_reads_bp += $_ foreach @counts;
 
                my $mark;
                if ( scalar @starts > 1 ) {
                    if ( $shear->{ $starts[0] } == $shear->{ $starts[1] } ) {
                        $mark = '#';
                        
                        # make feature darkest
                        if ($shear_id =~ /left/ ){
                            $real_shear->itemRgb('0,51,0');
                        }
                        if ($shear_id =~ /right/ ){
                            $real_shear->itemRgb('102,51,0');
                        }
                       
                    }
                    else {
                        $mark = '*';
                        # make feature darker
                        if ($shear_id =~ /left/){
                            $real_shear->itemRgb('51,102,0');
                        }
                        if ($shear_id =~ /right/ ){
                            $real_shear->itemRgb('153,76,0');
                        }

                    }

                }
               
                # rename shear;
                if ($mark){
                    $real_shear->name($mark."(".$shear->{$starts[0]}.'/'.$total_reads_bp."|".$real_shear->score.")_".$real_shear->name);
                }
                else{
                    $real_shear->name("(".$shear->{$starts[0]}.'/'.$total_reads_bp."|".$real_shear->score.")_".$real_shear->name);
                }

                if ( $real_shear->strand eq '+' ) {
                    if ($real_shear->chromStart < $starts[0]){
                        #say $real_shear->chromStart;
                        #say $starts[0];                        
                        #say "";
                        $real_shear->chromEnd($starts[0] + 1);
                        $real_shear->thickEnd($real_shear->chromEnd);
                        $real_shear->blockCount(2);
                        $real_shear->blockSizes('10,1');

                        my $blockStart = '0,'. ( $starts[0] - $real_shear->chromStart);
                        $real_shear->blockStarts($blockStart);
                        

                    }
                    else {
                        $self->log->error("Breakpoint cannot be before the shear in positive strand");
                        p $real_shear;
                        p $breakpoint_positions{$shear_id};
                        die;
                    }
                }
                elsif ( $real_shear->strand eq '-' ) {
                    if ($real_shear->chromStart > $starts[0]){
                        #say $real_shear->chromStart;
                        #say $starts[0];                        
                        #say "";
                        
                        $real_shear->chromStart($starts[0]);
                        $real_shear->thickStart($real_shear->chromStart);
                        $real_shear->blockCount(2);
                        $real_shear->blockSizes('1,10');

                        my $blockStart = '0,'. ( ($real_shear->chromEnd - $real_shear->chromStart) - 10 );
                        $real_shear->blockStarts($blockStart);

                    }
                    else {
                        $self->log->error("Breakpoint cannot be after the shear in negative strand");
                        p $real_shear;
                        p $breakpoint_positions{$shear_id};
                        die;
                    }
                }
            }
            push @features,$real_shear unless $real_shear->blockCount == 1;
        }
       

        my $track_line = $features[0]->track_line;
        $track_line =~ s/shears/breakpoints/g;

        open( my $out, '>', $self->output_file )
            || die "Cannot open/write file " . $self->output_file . "!";
       
        say $out $track_line;
        foreach my $feat (@features) {            
            print $out $feat->row;
        }
        close( $out );
 
    }

    method _is_close_to_shear_location (Str $shear_id, HashRef $position) {
         my $shear = $self->shears->{$shear_id};
         my $ok = 0;
         if ($shear->chrom eq $position->{chr}){
            if ( abs($shear->chromStart - $position->{start}) <= 1000 ){
                if (
                    ($position->{source} eq 'bait' && $position->{strand} ne $shear->strand) ||
                    ($position->{source} eq 'target' && $position->{strand} eq $shear->strand)
                    ){
                    if( ($shear->strand eq '+' && $position->{start} > $shear->chromStart )
                        || ($shear->strand eq '-' && $position->{start} < $shear->chromStart)
                    ){
                        $ok = 1;
                    }
                }
            }
         }
         return $ok;
    }

    method _get_brekpoint_position (HashRef $obj, Str $type where {$_ =~ /^target$|^bait$/}) {
        my ( $bp_chr, $bp_start, $bp_end );
        if ( $type eq 'bait' ) {

            #get strand
            $bp_chr = $obj->{chr};
            if ( $obj->{strand} eq '+' ) {

                # get 5'prime from bait
                $bp_start = $obj->{start};
                $bp_end  = $bp_start + 1;
            }
            else {
                $bp_end  = $obj->{end};
                $bp_start = $bp_end - 1;
            }
        }
        elsif ( $type = 'target' ) {
            $bp_chr = $obj->{chr};

            #get strand
            if ( $obj->{strand} eq '-' ) {

                # get 5'prime from bait
                $bp_start = $obj->{start};
                $bp_end  = $bp_start + 1;
            }
            else {
                $bp_end  = $obj->{end};
                $bp_start = $bp_end - 1;
            }
        }
        
        return {chr => $bp_chr, start => $bp_start, end => $bp_end, strand => $obj->{strand} ,source => $type };
    }

    method define_breakpoint (Str :$shear_id!, HashRef|Undef :$target, HashRef|Undef :$bait ) {
        # get chr and start position of breakpoint
        my $position;
        if ( $bait && $target ) {

            #check bait first
            $position = $self->_get_brekpoint_position( $bait, 'bait' );
            if ( $self->_is_close_to_shear_location( $shear_id, $position ) ) {
                return $position;
            }
            else {
                $position = $self->_get_brekpoint_position( $target, 'target' );
                if ( $self->_is_close_to_shear_location( $shear_id, $position ) ) {
                    return $position;
                }
                else {
                    return 0;
                }
            }
        }
        elsif ($bait) {
            $position = $self->_get_brekpoint_position( $bait, 'bait' );
            if ( $self->_is_close_to_shear_location( $shear_id, $position ) ) {
                return $position;
            }
            else {
                return 0;
            }
        }
        elsif ($target) {
            $position = $self->_get_brekpoint_position( $target, 'target' );
            if ( $self->_is_close_to_shear_location( $shear_id, $position ) ) {
                return $position;
            }
            else {
                return 0;
            }
        }
        else {
            $self->log->error("not target and no bait read, it shouldn't be sent o this function!");
            die;
        }
    }
}


class MyApp::FilterBreakpoints {
    extends 'MyApp';    # inherit log
    with 'MyApp::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;

    command_short_description q[Retrive breakpoints given a list of hostposts ids and shear index];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(i)],
        required      => 1,
        documentation => q[Hotstpos id list],
    );

    has_file 'breakpoints_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(b)],
        required      => 1,
        documentation => q[Breakpoint bed file],
    );

    method run {
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;
        $self->log->warn("==> Starting $cmd <==");

        # Code Here
        my $hts = $self->get_hotspots_shear_reads();
        
        my %shear_hotspot;

        foreach my $ht_id (keys %{$hts}) {
            foreach my $shear_id (keys %{$hts->{$ht_id}}) {
                $shear_hotspot{$shear_id} = $ht_id;
            }
        }
        
        my %selected_breaks;
        open( my $in, '<', $self->input_file )
            || die "Cannot open/read file " . $self->input_file . "!";
        while ( my $row = <$in> ) {
            chomp $row;
            my ( $ht_id, $gene ) = split "\t", $row;
            %selected_breaks = ( %selected_breaks, %{ $hts->{$ht_id} } );
        }
        close($in);
        
        $in = IO::Uncompress::AnyUncompress->new($self->breakpoints_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";
        
        while ( my $row = <$in> ){
            chomp $row;
            next if $row =~ /^track/;
            my @F = split "\t", $row;
            my $breakpoint_id = $F[3];
            $breakpoint_id =~s/.*_(left|right.*)/$1/g;
            if ($shear_hotspot{$breakpoint_id}){
                $F[3] .= ":". $shear_hotspot{$breakpoint_id} ;
            }
            else{
                die "Weird, I cant find the hotspot associated to this breakpoint:\n".$row."\n";
            }
           say join "\t", @F if $selected_breaks{$breakpoint_id};
            
        }
        
        close( $in );
        

        $self->log->warn("==> END $cmd <==");
    }
}


class MyApp::HotspotsDefinedByBreakpoints {
    extends 'MyApp';    # inherit log
    with 'MyApp::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
    use List::Util qw(min max);

    command_short_description q[Retrive breakpoints given a list of hostposts ids and shear index];

    has_file 'breakpoints_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(b)],
        required      => 1,
        must_exist    => 1,
        documentation => q[Breakpoint bed file],
    );

    has_file 'output_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(o)],
        required      => 1,
        documentation => q[Output bed file],
    );

    method run {
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;
        $self->log->warn("==> Starting $cmd <==");

        # Code Here
        my $hts = $self->get_hotspots_shear_reads();
        
        my %shear_hotspot;

        foreach my $ht_id (keys %{$hts}) {
            foreach my $shear_id (keys %{$hts->{$ht_id}}) {
                $shear_hotspot{$shear_id} = $ht_id;
            }
        }
        
        my $in = IO::Uncompress::AnyUncompress->new($self->breakpoints_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";
       
        my %hotspots;

        while ( my $row = <$in> ){
            chomp $row;
            next if $row =~ /^track/;
            my @F = split "\t", $row;
            my $breakpoint_id = $F[3];
            $breakpoint_id =~s/.*_(left|right.*)/$1/g;
            if ($shear_hotspot{$breakpoint_id}){
                my $ht_id = $shear_hotspot{$breakpoint_id}; 
                $F[3] .= ":". $ht_id ;

                $hotspots{$ht_id}{chr} = $F[0];
                push @{ $hotspots{$ht_id}{start} }, $F[1];
                push @{ $hotspots{$ht_id}{end} },   $F[2];
                $hotspots{$ht_id}{left}++ if $F[3] =~ /left/;
                $hotspots{$ht_id}{right}++ if $F[3] =~ /right/;
            }
            else{
                $self->log->warn("Weird, I cant find the hotspot associated to this breakpoint:\n".$row."\n");
            }
        }
        
        close( $in );
        my $track_line = $self->hotspot_file_track_line;
        $track_line =~ s/shears/breakpoints/g;
        open( my $out_bed, '>', $self->output_file.".bed" )
            || die "Cannot open/write file " . $self->output_file . ".bed!";
 
        open( my $out, '>', $self->output_file )
            || die "Cannot open/write file " . $self->output_file . "!";
       
        say $out_bed $track_line;
        foreach my $ht_id (sort {$a cmp $b} keys %hotspots) {
            my $cluster_id = $ht_id;
            $cluster_id =~ s/hotspot/cluster/g;
            my $ht = $hotspots{$ht_id};
            my $chr = $ht->{chr};
            my $start = min @{$ht->{start}};
            my $score = scalar @{$ht->{start}};
            my $end = max @{$ht->{end}};
            say $out_bed join "\t", ($chr, $start, $end, $cluster_id, $score, '+', $start, $end, '102,0,51');
            my ($left,$right) = ($ht->{left},$ht->{right});
            $left |= 0;
            $right |= 0;
            say $out join "\t", ($chr, $start, $end, $cluster_id, ($end - $start), $score, $left,$right, $ht_id);
        }
        close( $out_bed );
        close( $out );
 
        $self->log->warn("==> END $cmd <==");
    }
}



class Main {
    import MyApp;
    MyApp->new_with_command->run();
}
