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

               next if $align->qual < 20  || $align->length < 36;

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


class MyApp::RetrieveReads {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
    use Bio::SeqIO;
    use Data::Printer;
    use File::Basename;
    
    command_short_description q[Retrieve reads given index files for shears and hotspots];

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
                die $self->hotspot_index_file . " doesn't seem to be an hotspot index file!";
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
        }

        #return \%ht_reads;
        return \%reads_ht;
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
                $self->log->error("Unmapped read found. You shouldn't have unmapped reads in this file. Check your bam file:". $qname);
                die;
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
               say $qname;
               say $clipped_seq;

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


class Main {
    import MyApp;
    MyApp->new_with_command->run();
}
