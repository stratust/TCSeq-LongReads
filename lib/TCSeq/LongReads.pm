use MooseX::Declare;
use Method::Signatures::Modifiers;
use feature qw(say);

class TCSeq::LongReads {
    # ABSTRACT: Handle BAM files
    use Carp;
    use Bio::Seq;
    use Bio::SeqIO;
    use Bio::DB::Sam;
    use String::Approx 'amatch';
    use Log::Any qw($log);
    use Data::Printer deparse => 1, sort_keys => 0;

    has 'barcode' => (
        is            => 'ro',
        isa           => 'Str',
        required      => 1,
        documentation => 'Barcode sequence',
    );
 
    has 'linkers' => (
        is            => 'ro',
        isa           => 'ArrayRef[Str]',
        required      => 1,
        documentation => 'Linker Sequence without barcode',
    );
 
    has 'barcode_position' => (
        traits        => ['Hash'],
        is            => 'rw',
        isa           => 'HashRef',
        documentation => 'Count position of barcode in sequences',
        handles       => {
            set_barcode_position => 'set',
            get_barcode_position => 'get',
        },
    );

    has 'true_barcode_position' => (
        is  => 'rw',
        isa => 'HashRef',
        documentation =>
            'Count position of true barcode (has linker if in the middle) in sequences',
    );

    has 'output_dir' => (
        is       => 'rw',
        isa      => 'Str',
        required => 1,
    );

    has 'bait_file' => (
        is       => 'rw',
        isa      => 'Str',
        required => 1,
    );

    has 'target_file' => (
        is       => 'rw',
        isa      => 'Str',
        required => 1,
    );

    has 'target' => (
        is      => 'rw',
        isa     => 'Bio::SeqIO',
        lazy    => 1,
        builder => '_build_target'
    );

    has 'bait' => (
        is      => 'rw',
        isa     => 'Bio::SeqIO',
        lazy    => 1,
        builder => '_build_bait'
    );


    our %barcode_position;         # Keep position of all barcodes
    our %true_barcode_position;    # Keep position of all barcodes with linker sequence at 5' end

    method _build_bait {

        my $bait = Bio::SeqIO->new(
            -file   => '>' . $self->output_dir . '/' . $self->bait_file,
            -format => 'Fasta'
        );
        return $bait;
    }

    method _build_target {

        my $target = Bio::SeqIO->new(
            -file   => '>' . $self->output_dir . '/' . $self->target_file,
            -format => 'Fasta'
        );
        return $target;
    }

=head2 annotate_primer

 Title   : annotate_primer 
 Usage   : $obj->annotate_primer(bam_file_1 => 'filename', bam_file_2 => 'filename')
 Function: Given a pair of BAM files mapped against the left and right primers split them into bait and target
 Returns : Nothing, just write fasta files
 Args    : Hash with with BAM filenames

=cut 

    method annotate_primer ( :$bam_file_1, :$bam_file_2 ) {
        my %sequence;
        $self->_parse_bam($bam_file_1,"P1",\%sequence);
        $self->_parse_bam($bam_file_2,"P2",\%sequence);
        $self->_filter_pairs(\%sequence);
    }


=head2 _parse_bam

 Title   : _parse_bam
 Usage   : _parse_bam('filename',[P1| P2],\%hash)
 Function: Parses a BAM file with information about primer and write if is bait or not in \%hash.
 Returns : Nothing, writes in \%hash; 
 Args    : Filename, [ "P1" | "P2" ], \%hash

=cut 

    method _parse_bam ($bam_file,Str $pair where [qw/P1 P2/], HashRef $sequence) {
        
        my $bame          = Bio::DB::Bam->open($bam_file);
        my $header       = $bame->header;
        my $target_count = $header->n_targets;
        my $target_names = $header->target_name;
        my $i;

        while ( my $align = $bame->read1 ) {
            my ( $qname, $query_start, $query_end, $query_dna );

            $qname = $align->qname;

            $query_dna = $align->qseq;

            #my $this = \$sequence{$qname}{'P1'};

            if ( $align->unmapped ) {
                $sequence->{$qname}{$pair}{is_bait}      = 0;
                $sequence->{$qname}{$pair}{have_primers} = 0;
            }
            else {
                my $seqid  = $target_names->[ $align->tid ];
                my $strand = $align->strand;
                my $seq_after_primer;

                if ( $strand == 1 ) {
                    $query_start = $align->query->start - 1;
                    $query_end   = $align->query->end;
                    $sequence->{$qname}{$pair}{$seqid}{after}  = substr($query_dna,$query_end,15);
 
                }
                # Negative strand is complemented reversed in BAM file
                else {
                    $sequence->{$qname}{$pair}{$seqid}{after}  = substr($query_dna,$align->query->end,15);
 
                    my $q_length = $align->l_qseq;
                    $query_end   = $q_length - $align->query->start + 1;
                    $query_start = $q_length - $align->query->end ;

                    # rever complement query
                    $query_dna = $self->_reverse_complement( $query_dna );

               }

                $sequence->{$qname}{$pair}{have_primers}++;
                $sequence->{$qname}{$pair}{$seqid}{pos}  = [$query_start,$query_end];
               
                # Define if is bait
                if ( $query_start >= 0 && $query_start <= 5 ) {
                    $sequence->{$qname}{$pair}{is_bait} = $seqid;
                }
            }

            $sequence->{$qname}{$pair}{seq} = $query_dna;

            # Find Barcode
            $sequence->{$qname}{$pair}{has_barcode} = $self->_search_barcode($query_dna);
            $sequence->{$qname}{$pair}{has_barcode_complement} = $self->_search_barcode_complement($query_dna);

            #$sequence{$qname}{$pair}{barcodes} = \@barcodes;

#                say join "\t",($align->qname, $seqid, $query_start, $query_end, $strand, $cigar, $query_dna );
            $i++;
            #last if $i == 1000;
        }
 
    }


    method _filter_pairs ($sequence) {        

        foreach my $id (keys %{$sequence}) {
            my $err;
            
            unless ( $sequence->{$id}->{P1} ) {
                $err .= "Cannot find P1!";
            }

            unless ( $sequence->{$id}->{P2} ) {
                $err .= "Cannot find P2!";
            }
            
            if ($err){
                $log->error("Problem: $err in $id ");
                #confess $err;
            }
 
            next unless $sequence->{$id}->{P1};
            next unless $sequence->{$id}->{P2};
             
            $self->_define_bait_target($id, $sequence->{$id}->{P1},$sequence->{$id}->{P2});
        
        }
    }


=head2 _define_bait_target

 Title   : _define_bait_target
 Usage   : _define_bait_target()
 Function: 
 Returns : 
 Args    : 

=cut 

    method _define_bait_target ( $qname, HashRef $s1,HashRef $s2) {
        #my $P1_trash = Bio::SeqIO->new( -file => '>P1_trash.fa', -format => 'fasta' );
        #my $P2_trash = Bio::SeqIO->new( -file => '>P2_trash.fa', -format => 'fasta' );

        if ($s1->{is_bait}){
            if ($s2->{has_barcode}->{last_barcode_pos}){
                #perfect
                # check reverse barcode and trim sequences
                $self->_trim_sequences($s1,$s2);

                $self->bait->write_seq(
                    $self->_build_bioseq_object( $qname, $s1, $s1->{is_bait} ) 
                );
                $self->target->write_seq(
                    $self->_build_bioseq_object( $qname, $s2, $s1->{is_bait} ) 
                );
            }
            elsif( $s2->{is_bait} ){
                #two baits
            }
            # empty sequence
            else {

            }
        }
        elsif ($s1->{has_barcode}->{last_barcode_pos}){
             if ($s2->{is_bait}){
                #perfect
                # check reverse barcode and trim sequences
                $self->_trim_sequences($s2,$s1);

                # Write into fasta file
                $self->bait->write_seq( 
                    $self->_build_bioseq_object( $qname, $s2, $s2->{is_bait} ) 
                );
                $self->target->write_seq(
                    $self->_build_bioseq_object( $qname, $s1, $s2->{is_bait} ) 
                );
            }
            elsif( $s2->{has_barcode}->{last_barcode_pos} ){
                #two barcodes
            }
        }
        # s1 is not bait and theres no barcodde
        else {
            

        }
           
    }

    
=head2 _trim_sequences

 Title   : _trim_sequences
 Usage   : _trim_sequences()
 Function: 
 Returns : 
 Args    : 

=cut 

    method _trim_sequences ($bait,$target) {
        
        $bait->{trimmed_seq}   = $bait->{seq};
        $target->{trimmed_seq} = $target->{seq};

        if ($bait->{has_barcode_complement}{sequence_before_barcode_complement}){
        
            my $bait_seq = $bait->{has_barcode_complement}{sequence_before_barcode_complement}; 
            my $target_seq = $target->{has_barcode}{seq_after_barcode}; 
            my $match = amatch($bait_seq, [ '7%' ], $target_seq);
            
            # trim sequence
            if ($match) {
                $bait->{trimmed_seq} = substr( 
                    $bait->{seq}, 
                    0,
                    $bait->{has_barcode_complement}->{pos}->[0] 
                );
            }
        } 

        # look for primer position in target ;
        my $primer = $bait->{is_bait}; # right or left
        
        if ( $target->{$primer} ) {
            my $match = amatch( $target->{$primer}->{after},
                ['7%'], $bait->{$primer}->{after} );
            # trim sequence
            if ($match) {
                $target->{trimmed_seq} =
                  substr( $target->{seq}, 0, $target->{$primer}->{pos}->[0] );
            }
        }

        # remove barcode
        $target->{trimmed_seq} = substr( $target->{seq}, $target->{has_barcode}->{last_barcode_pos}->[1] );

    } 


=head2 _build_bioseq_object

 Title   : _build_bioseq_object
 Usage   : _build_bioseq_object()
 Function: 
 Returns : 
 Args    : 

=cut 

    method _build_bioseq_object ($qname, HashRef $seq, Str $bait_primer) {
        my $dna;
        if ($seq->{trimmed_seq}){
            $dna = $seq->{trimmed_seq};
        }
        else {
            $dna = $seq->{seq};
        }
        
        my $id = "$qname-$bait_primer";
        my $obj = Bio::Seq->new(
            -id               => $id,
            -seq              => $dna
        );
        
        return $obj;
    }


    method _search_barcode (Str $sequence) {
        my %aux;

        my @barcodes = &match_all_positions( $self->barcode, $sequence );
        
        if (@barcodes) {
            
            $aux{n_barcodes} = scalar @barcodes;
            $aux{barcode_pos} = \@barcodes;
            
            foreach my $pos (  @barcodes) {
                my $barcode_start = $pos->[0] ;
                my $barcode_end = $pos->[1] ;
                $barcode_position{$barcode_start}++;
                
                # look for linker if barcode is not in the beginning
                my $has_linker;
                if ( $barcode_start > 0 ) {
                    my $debug;
                    
                    # Look for both linkers
                    foreach my $l ( @{ $self->linkers } ) {
                        my ($seq_before_barcode);
                        my $linker = $l;

                        if ( $barcode_start == length($linker) ) {
                            $seq_before_barcode =
                              substr( $sequence, 0, $barcode_start );
                        }
                        elsif ( $barcode_start < length($linker) ) {
                            $seq_before_barcode =
                              substr( $sequence, 0, $barcode_start );
                            $linker =
                              substr( $linker, -length($seq_before_barcode) );
                        }
                        else {
                            $seq_before_barcode =
                              substr( $sequence,
                                ( $barcode_start - length($linker) ),
                                length($linker) );
                        }
                        
                        my $match = amatch($linker, [ '7%' ], $seq_before_barcode);
                        
                        if ($match){
                            $has_linker++;
                            $true_barcode_position{$barcode_start}{linkers}{$l}++;
                            #if ($barcode_start > 237){
                            #    say "Linker: $linker";
                            #    say "Before Barcode: $seq_before_barcode";
                            #    say "Start: $barcode_start";
                            #    say $name;
                            #    say $sequence;
                            #}
                        }
                    }
                    if ($has_linker){
                        $true_barcode_position{$barcode_start}{count}++;
                        $aux{last_barcode_pos} = $pos;
                        
                        $aux{seq_after_barcode} = substr($sequence,$barcode_end, 15);
                    }
                }
                else{
                    $true_barcode_position{$barcode_start}{count}++;
                    $aux{last_barcode_pos} = $pos;
                    $aux{seq_after_barcode} = substr($sequence,$barcode_end, 15);
                }
                
            }
        }
        
        return \%aux;
    }

    method _search_barcode_complement (Str $sequence ) {
        my %hash;

        my $reversed_barcode = $self->_reverse_complement( $self->barcode );

        my @barcodes = &match_all_positions( $reversed_barcode, $sequence );

        if (@barcodes) {
            my $pos = pop @barcodes;
            my $barcode_start = $pos->[0];
            my $barcode_end = $pos->[1];

            my $aux = substr($sequence, ($barcode_start - 15 ) , 15);
            # save in right orientation to compare with barcode
            $hash{sequence_before_barcode_complement} = $self->_reverse_complement($aux);
            $hash{pos} = $pos;
        }
        return \%hash;
    }



# Auxiliary methods

=head2 _reverse_complement

 Title   : _reverse_complement
 Usage   : $self->_reverse_complement($dna)
 Function: Reverse complement a DNA string. 
 Returns : A complement reverse DNA string.
 Args    : DNA string

=cut 

    method _reverse_complement ($dna) {
        #reverse the DNA sequence
        my $revcomp = reverse($dna);

        # complement the reversed DNA sequence
        $revcomp =~ tr/ACGTacgt/TGCAtgca/;
        return $revcomp;
    }


    sub match_positions {
        my ($regex, $string) = @_;
        return if not $string =~ /$regex/;
        return ($-[0], $+[0]);
    }
    

    sub match_all_positions {
        my ($regex, $string) = @_;
        my @ret;
        while ($string =~ /$regex/g) {
            push @ret, [ $-[0], $+[0] ];
        }
        return @ret
    }
}
