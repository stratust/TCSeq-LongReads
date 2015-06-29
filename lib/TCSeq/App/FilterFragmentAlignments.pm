use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
 
class TCSeq::App::FilterFragmentAlignments {
    extends 'TCSeq::App'; # inherit log
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
