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
        required      => 0,
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

        if ( $self->bait_fasta_file ) {
            my $in = Bio::SeqIO->new( -file => $self->bait_fasta_file, -format => 'fasta' );
            my ($name,$path,$suffix) = fileparse($self->bait_fasta_file,['.fasta','.fa']);
            my $outfile = $path."hotspot_selected_".$name;
            my $out = Bio::SeqIO->new( -file => '>'.$outfile, -format => 'fasta' );

            while ( my $seq = $in->next_seq ) {
                if ( $reads->{ $seq->id } ) {
                    my $aux = $reads->{ $seq->id };
                    $seq->id( $seq->id . "|$aux->{shear_id}|$aux->{hotspot_id}" );
                    $out->write_seq($seq);
                }
            }
        }
    }
}


class Main {
    import MyApp;
    MyApp->new_with_command->run();
}
