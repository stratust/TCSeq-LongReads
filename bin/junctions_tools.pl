#!/usr/bin/env perl

use MooseX::Declare;
use Method::Signatures::Modifiers;
use feature qw(say);
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

class MyApp::Classify {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;   # important
    use MooseX::FileAttribute;
    use Carp;
    use Bio::DB::Sam;
    use List::Util qw(max min sum);
    use Text::Padding;
    use lib 'lib';
    use TCSeq::Target::Classification;
    use Data::Printer deparse => 1, sort_keys => 0;

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'i',
        required      => 1,
        must_exist    => 1,
        documentation => 'Input file to be processed',
    );
    
    has_file 'target_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 't',
        required      => 0,
        must_exist    => 1,
        documentation => 'Target file to be processed',
    );
   
    has_file 'fasta_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'f',
        required      => 0,
        must_exist    => 1,
        documentation => 'Chromosome fasta file',
    );

    has 'bait_position' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        is            => 'rw',
        isa           => 'Str',
        cmd_aliases   => 'b',
        required      => 0,
        default       => 'left=chr15:61818182-61818339,right=chr15:61818343-61818507',
        documentation => 'Bait position (from primer to break).'
    );

    has 'enzime_restriction_size' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        is            => 'rw',
        isa           => 'Int',
        cmd_aliases   => 'e',
        required      => 0,
        default       => 4,
        documentation => 'How much restriction enzime will cleave from bait site.',
    );

    has_file 'alignment_output_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => 'a',
        required      => 0,
        must_exist    => 0,
        default       => 'alignments_file.txt',
        documentation => 'Name given for alignment file generated.',
    );

    has 'output_path' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        is            => 'rw',
        isa           => 'Str',
        cmd_aliases   => 'o',
        required      => 0,
        default       => '.',
        documentation => 'Path where the genereated files will be placed',
    );

    has 'fragment_size' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        is            => 'rw',
        isa           => 'Int',
        cmd_aliases   => 's',
        required      => 1,
        default       => 36,
        documentation => 'Mininum fragment size to be analyzed (for bait and target).',
    );

    has 'min_mapq' => (
        traits      => ['AppOption'],
        cmd_type    => 'option',
        is          => 'rw',
        isa         => 'Int',
        cmd_aliases => 'q',
        required    => 1,
        default     => 30,
        documentation =>
            'Mininum SAM MAPQ each fragment should have to be analyzed (for bait and target).',
    );
    
    has '_baits' => (
        is      => 'rw',
        isa     => 'HashRef',
        lazy    => 1,
        builder => '_build_baits',

        documentation => 'Hold  bait info'
    );

    method _build_baits {
        my %hash;
        my @baits = split /\s*,\s*/, $self->bait_position;
        foreach my $bait (@baits) {
            if ( $bait =~ /(left|right)\=(chr\S+):(\d+)-(\d+)/ ) {
                $hash{$1} = {
                    chr   => $2,
                    start => $3,
                    end   => $4
                };
                $self->log->debug(p %hash);
            }
            else {
                die "Problem with bait_position string! (".$self->bait_position.")" ;
            }
        }
        return ( \%hash );
    }

    # Global variables
    our $reads_to_clustering_LR;
    our $reads_to_clustering;
    our $uniq_bait_without_target;
    our $uniq_bait_with_target;
    our $uniq_bait_with_target_accepted;
    our $uniq_bait_before_break;
    our $bait_blunt_cut;
    our $bait_pseudoblunt_cut;
    our $bait_no_cut;
    our $bait_cut_with_deletions;
    our $bait_pseudocut_with_deletions;
    our $invalid_reads;
    our $total_reads_mapped;
    
    # Description of this command in first help
    sub abstract { 'Classify rearrangements in a BAM file'; }

=head2 match_all_positions

 Title   : match_all_positions
 Usage   : match_all_positions($regex,$string)
 Function: Given a string and a regex pattern return all start,end for each
 match
 Returns : An array of arrays with [ star, end ] position of matches
 Args    : pattern and a string

=cut 

    method match_all_positions( Str $regex, Str $string ) {
        my @ret;

        while ( $string =~ /$regex/g ) {
            push @ret, [ $-[0], $+[0] ];
        }

        return @ret;
    }


    method get_start_end( Str $regex, Str $string ) {
        my @pos = $self->match_all_positions( $regex, $string );
        return ( $pos[0]->[0], ( $pos[$#pos]->[1] - $pos[0]->[0]));
    }


    method fix_padded_alignment( Object $align ) {
        my ( $ref, $match, $query ) = $align->padded_alignment;
        my ( $offset, $length ) = $self->get_start_end( '\|', $match );
        my $new_ref   = substr $ref,   $offset, $length;
        my $new_match = substr $match, $offset, $length;
        my $new_query = substr $query, $offset, $length;
        return ($new_ref,$new_match,$new_query);
    }


    method split_string( Str $string, Num $step = 60 ) {
        my @splited = $string =~ /.{1,$step}/g;
        return @splited;
    }


    method pretty_alignment( Object $align) {

        # Getting the alignment fixed.
        my ( $ref, $match, $query ) = $self->fix_padded_alignment($align);
        
        # Defining the padding for position numbers based on max chromosome
        # position
        my $string_pos_length = max(length($align->start), length($align->end));
        my $read = $align->query;
        my $pad = Text::Padding->new();
        
        
        # Define the reference start (always '+' strand)
        my $ref_start = $align->start;
        
        # Define the query start (strand dependent)
        my $query_start;
        
        # Keep the ">>>" or "<<<" to add to match line
        my $direction;

        # Strand matters
        # Postitive strand
        if ( $align->strand == 1 ) {
            $query_start = $align->query->start;
            $direction .= '>' for 1 .. $string_pos_length;
        }
        # Negative strand
        else{
            $query_start = length($align->query->seq->seq) - $align->query->start;
            $direction .= '<' for 1..$string_pos_length;
        }
 
        # Spliting sequence
        my $step = 60;
        my @refs    = $self->split_string( $ref,   $step );
        my @matches = $self->split_string( $match, $step );
        my @queries = $self->split_string( $query, $step );


        # Building Alignment representation
        #==========================================================================
        my @alignment;

        for ( my $i = 0 ; $i <= $#refs ; $i++ ) {
            # Calculate position in reference (indels are not taken into account)
            # -------------------------------------------------------------------
            my $ref_part = $refs[$i];
            $ref_part =~ s/\-//g;

            # remove one because is zero based
            my $ref_part_length = length($ref_part) - 1;

            push(
                @alignment,
                "\t"
                  . $pad->left( $ref_start, $string_pos_length ) . " "
                  . $refs[$i] . " "
                  . $pad->left(
                    ( $ref_start + $ref_part_length ),
                    $string_pos_length
                  )
            );

            # Calculate match line
            # --------------------------
            push( @alignment,
                "\t" . $direction . " " . $matches[$i] . " " . $direction );

            # Calculate position in query (indels are not taken into account)
            # -------------------------------------------------------------------
            my $query_part = $queries[$i];
            $query_part =~ s/\-//g;

            # remove one because is zero based
            my $query_part_length = length($query_part) - 1;

            if ( $align->strand == 1 ) {

                push(
                    @alignment,
                    "\t"
                      . $pad->left( $query_start, $string_pos_length ) . " "
                      . $queries[$i] . " "
                      . $pad->left(
                        ( $query_start + $query_part_length ),
                        $string_pos_length
                      )
                );
                
                # Query step if strand +
                $query_start += $query_part_length + 1;

            }
            else {

                push(
                    @alignment,
                    "\t"
                      . $pad->left( $query_start, $string_pos_length ) . " "
                      . $queries[$i] . " "
                      . $pad->left(
                        ( $query_start - $query_part_length ),
                        $string_pos_length
                      )
                );

                # Query step if strand -
                $query_start -= $query_part_length + 1;

            }

            # Reference step (is always +)
            $ref_start += $ref_part_length + 1;

        }

        return @alignment;    

    }


=head2 Clustering logic

    Given a read splitting in two fragments in the same chromosome:

    ***********************
    * Legend:             *
    *                     *
    * > or < : direction  *
    *                     *
    * # : break junction  *
    *                     *
    ***********************

    When a bait(primer) and target have the same orientation

                ----------       E      S
                | Primer |------>#      #-------->
                ----------

    S           ----------       E
    #------->   | Primer |------>#
                ----------
 
   Possibly a microhomology:

                ----------       E  
                | Primer |------>#      
                ----------   #------->
                             S
  
    
    When a bait(primer) and target have different orientation

                ----------       E               E
                | Primer |------>#      <--------#
                ----------

            E   ----------       E
    <-------#   | Primer |------>#
                ----------


    This shouldn't be a microhomology because reads have different directions

                ----------       E  
                | Primer |------>#      
                ----------   <-------#
                                     E
   
   RULES OF THE THUMB:
   
   1) Bait and targets in the same direction have junctions in END of the Bait
   and in the START of the target
   2) Bait and targets in different directons have junctions in END of the Bait
   and in the END of the target
   3) Microhomology just occurs when the bait and target are in the same
   strand


   FOR REVERSE BAIT

   When a bait(primer) and target have the same orientation

             E       S       ---------- 
    <--------#       #<------| Primer | 
                             ----------
    
                     S       ----------             E
                     #<------| Primer |    <--------#
                             ----------
 
   Possibly a microhomology:

                     S       ---------- 
                     #<------| Primer | 
               <--------#    ----------
                        E
    
    When a bait(primer) and target have different orientation

    S                S       ---------- 
    #-------->       #<------| Primer | 
                             ----------
    
                     S       ----------    S        
                     #<------| Primer |    #-------->
                             ----------


    This shouldn't be a microhomology because reads have different directions

                     S       ---------- 
                     #<------| Primer | 
               #-------->    ----------
               S         
 
   RULES OF THE THUMB:
   
   1) Bait and targets in the same direction have junctions at the START of the Bait
   and at the END of the target
   2) Bait and targets in different directons have junctions at the START of the Bait
   and at the START of the target
   3) Microhomology just occurs when the bait and target are in the same
   strand


=cut
    
    method clustering_alignments( HashRef $alignments_to_cluster) {
        my %cluster;
        foreach my $read_id ( keys %{$alignments_to_cluster} ) {
            # INDEXING BY BREAK POINT (removing PCR duplicates)
            # Building key
            my $primer_name;
            if ($read_id =~/left/) {
                $primer_name = 'left';
            }
            elsif ($read_id =~ /right/) {
                $primer_name= 'right';
            }
            else{
                die "No left or right in read name";
            }

            # If is bait only, key was already built
            if ($alignments_to_cluster->{$read_id}->{key}){
                my $this_key = $alignments_to_cluster->{$read_id}->{key}.'-'.$primer_name;
                push @{ $cluster{$this_key} },
                  $alignments_to_cluster->{$read_id};
                next;
            }
            
            if ($primer_name =~ /left/){
                $self->_clustering_reads($alignments_to_cluster->{$read_id},$primer_name,\%cluster);
            }
            elsif ($primer_name =~ /right/){
                
                $self->_clustering_reads_right($alignments_to_cluster->{$read_id},$primer_name,\%cluster);
            }
            else{
                $self->log->error("Cannot attribute primer left or right to: $primer_name");
            }

        }

        my @summary;
        my $total_clusters = scalar keys %cluster;

        push @summary, "\t- Total number of clusters: "
          . $total_clusters . "("
          . ($total_clusters / $reads_to_clustering_LR * 100)."%)";

        my @clusters_size;
        foreach my $k (keys %cluster){
            push @clusters_size, scalar @{$cluster{$k}};
        }

        my ($min_cluster_size, $max_cluster_size,$avg_cluster_size) =
        (min(@clusters_size), max(@clusters_size),(sum(@clusters_size)/scalar(@clusters_size)));
        
        push @summary, "\t- Mininum number of reads in a cluster: "
          . $min_cluster_size;

        push @summary, "\t- Maximum number of reads in a cluster: "
          . $max_cluster_size;

        push @summary, "\t- Average number of reads in a cluster: "
          . $avg_cluster_size;
        
        push @summary, "\t- Sum of read in clusters: "
          . sum(@clusters_size);


        $self->log->debug(join "\n",@summary);

        return \%cluster;
    }


    method _clustering_reads(HashRef $this_read, Str $primer_name, HashRef $cluster_ref) {
            my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };
 
            # Bio::DB::Sam alignment object
            my $bait = $this_read->{bait};
            my $bait_strand = '+';

            $self->log->trace("Read ID: ".$bait->qname);
            $self->log->trace("------------------------------------------------");
 
            $bait_strand = '-' if $bait->strand == -1;

            # Get read start and end
            my ( $bait_query_end, $bait_query_start );

            # For reads strand matters
            if ( $bait_strand eq '+' ) {
                $bait_query_end   = $bait->query->end;
                $bait_query_start = $bait->query->start;
            }
            else {
                my $bait_length = length( $bait->query->seq->seq ); 
                $bait_query_end =   (  $bait_length - $bait->query->end );
                $bait_query_start = (  $bait_length - $bait->query->start );
            }

            #Correcting pseudoblunt targens in split-reads:
            # verify if bait pass througth breakpoint
            my $corrected_bait_end = $bait->end;
            if ( $bait->end > ( $end - 1 ) ) {
                $corrected_bait_end = $end;
            }
            
            # Start key
            my $key = $bait->seq_id . '_' . $corrected_bait_end . '_' . $bait_strand;

            my %bait_targets;
            if ( $this_read->{bait_targets} ) {
                %bait_targets = %{ $this_read->{bait_targets} };

                # Sorting by read start
                foreach my $query_start ( sort { $a <=> $b } keys %bait_targets ) {

                    # Usually Should have just one splice here
                    foreach my $target ( @{ $bait_targets{$query_start} } ) {

                        my $chr    = $target->seq_id;
                        my $strand = '+';
                        $strand = '-' if $target->strand == -1;

                        my ( $target_query_end, $target_query_start );

                        if ( $strand eq '+' ) {
                            $target_query_end   = $target->query->end;
                            $target_query_start = $target->query->start;
                        }
                        else {
                            my $seq_length = length( $target->query->seq->seq );
                            $target_query_end   = ( $seq_length - $target->query->end );
                            $target_query_start = ( $seq_length - $target->query->start );
                        }

                        # Keep diff between bait and target
                        # Information necessary to know if is blunt, insertion or deletion
                        my $diff_read;
                        $self->log->trace( "\ttarget_query_start " . $target_query_start );
                        $self->log->trace( "\ttarget_query_end " . $target_query_end );
                        $self->log->trace( "\tbait_query_start " . $bait_query_start );
                        $self->log->trace( "\tbait_query_end " . $bait_query_end );


                        if ( $strand eq $bait_strand ) {

                            if ( $bait_strand eq '+' ) {
                                $diff_read =
                                  $target_query_start - $bait_query_end;
                                $diff_read += -1;
                            }
                            else {
                                $self->log->warn("This cannot happen!");
                                next;
                                #$diff_read =
                                #  $target_query_end - $bait_query_start;
                            }

                            $key .= '|'
                              . $target->seq_id . '_'
                              . $target->start . '_'
                              . $strand;

                        }
                        else {
                            if ( $bait_strand eq '+' ) {
                                $diff_read =
                                  $target_query_end - $bait_query_end;
                                $diff_read += -1;
                            }
                            else {
                                $self->log->warn("This cannot happen!");
                                next;
                                #$diff_read =
                                #  $bait_query_start - $target_query_start;
                            }

                            $key .= '|'
                              . $target->seq_id . '_'
                              . $target->end . '_'
                              . $strand;
                        }

                        # Add diff to key
                        $key .= '_' . $diff_read .'-'.$primer_name;
                    }
                }

                $self->log->trace("\tDefined key: $key");

                # Looking for targets
                $self->cluster_with_targets($this_read, $cluster_ref, $key)
 
            }

            unless ($self->target_file){
                push @{ $cluster_ref->{$key} }, $this_read;
            }
    }


    method _clustering_reads_right(HashRef $this_read, Str $primer_name, HashRef $cluster_ref) {
            my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };
            
           # Bio::DB::Sam alignment object
            my $bait = $this_read->{bait};
            $self->log->trace("Read ID: ".$bait->qname);
            $self->log->trace("------------------------------------------------");
 
            my $bait_strand = '+';

            $bait_strand = '-' if $bait->strand == -1;

            # Get read start and end
            my ( $bait_query_end, $bait_query_start );

            # For reads strand matters
            if ( $bait_strand eq '+' ) {
                $bait_query_end   = $bait->query->end;
                $bait_query_start = $bait->query->start;
            }
            else {
                my $bait_length = length( $bait->query->seq->seq ); 
                $bait_query_end =   (  $bait_length - $bait->query->end );
                $bait_query_start = (  $bait_length - $bait->query->start );
            }

            #Correcting pseudoblunt targens in split-reads:
            # verify if bait pass througth breakpoint
            my $corrected_bait_end = $bait->start;
            if ( $bait->start > ( $start - 1 ) ) {
                $corrected_bait_end = $start;
            }
            
            # Start key
            my $key = $bait->seq_id . '_' . $corrected_bait_end . '_' . $bait_strand;

            my %bait_targets;
            if ( $this_read->{bait_targets} ) {
                %bait_targets = %{ $this_read->{bait_targets} };
                
                # Sorting by read start
                foreach my $query_start ( sort { $a <=> $b } keys %bait_targets ) {
                    
                    # Usually Should have just one splice here
                    foreach my $target ( @{ $bait_targets{$query_start} } ) {

                        my $chr    = $target->seq_id;
                        my $strand = '+';
                        $strand = '-' if $target->strand == -1;

                        my ( $target_query_end, $target_query_start );

                        if ( $strand eq '+' ) {
                            $target_query_end   = $target->query->end;
                            $target_query_start = $target->query->start;
                        }
                        else {
                            my $seq_length = length( $target->query->seq->seq );
                            $target_query_end   = ( $seq_length - $target->query->end );
                            $target_query_start = ( $seq_length - $target->query->start );
                        }

                        # Keep diff between bait and target
                        # Information necessary to know if is blunt, insertion or deletion
                        my $diff_read;
                        $self->log->trace( "\ttarget_query_start " . $target_query_start );
                        $self->log->trace( "\ttarget_query_end " . $target_query_end );
                        $self->log->trace( "\tbait_query_start " . $bait_query_start );
                        $self->log->trace( "\tbait_query_end " . $bait_query_end );

                        if ( $strand eq $bait_strand ) {

                            if ( $bait_strand eq '+' ) {
                                #die "Error: something is wrong here!"
                                $self->log->warn("This cannot happen!");
                                next;
                                #$diff_read =
                                #  $target_query_start - $bait_query_start;
                            }
                            else {

                                $diff_read =
                                  $target_query_end - $bait_query_start;

                                $diff_read += -1;
                            }

                            $key .= '|'
                              . $target->seq_id . '_'
                              . $target->end . '_'
                              . $strand;

                        }
                        else {
                            if ( $bait_strand eq '+' ) {
                                # this should not occur;
                                #$diff_read =
                                #  $target_query_end - $bait_query_end;
                                #die "Error: something is wrong here!"
                                $self->log->warn("This cannot happen!");
                                next;
                            }
                            else {

                                $diff_read =
                                  $target_query_start - $bait_query_start;

                                $diff_read += -1;
                            }

                            $key .= '|'
                              . $target->seq_id . '_'
                              . $target->start . '_'
                              . $strand;
                        }

                        # Add diff to key
                        $key .= '_' . $diff_read .'-'.$primer_name;
                    }
                }
               
                $self->log->trace("\tDefined key: $key");

                # Looking for targets
                $self->cluster_with_targets($this_read, $cluster_ref, $key)
            }

            unless ($self->target_file){
                push @{ $cluster_ref->{$key} }, $this_read;
            }
    }


    method cluster_with_targets (HashRef $this_read, HashRef $cluster_ref, Str $key) {
        if ( $this_read->{real_targets} ) {

            $self->log->trace("\t\tLooking for targets:");
            $self->log->trace("\t\t---------------------------------------------");

            my @aux = split /\|/, $key;

            if ( $aux[$#aux] =~ /^(chr\w+)_(\d+).*/ ) {
                my ( $b_target_chr, $b_target_start ) = ( $1, $2 );

                $self->log->trace("\t\tFrom bait: chrom($b_target_chr), start($b_target_start)");

                foreach my $t ( @{ $this_read->{real_targets} } ) {
                    if ( $t->{chr} eq $b_target_chr ) {
                        my $prime5 = $t->{start};
                        if ( $t->{strand} eq "-" ) {
                            $prime5 = $t->{end};
                        }

                        $self->log->trace(
                            "\t\tSame chr:" . $t->{chr} . "_" . $prime5 . "_" . $t->{strand} );

                        my $distance_from_bait = abs( $b_target_start - $prime5 );

                        $self->log->trace("\t\tDistance from bait: $distance_from_bait");

                        if ( $distance_from_bait <= 1000 ) {
                            $key .= '_(' . $t->{chr} . '_' . $prime5 . ')';
                            push @{ $cluster_ref->{$key} }, $this_read;
                        }
                    }
                }
            }
        }
    }


=head2 show_clusters_alignment

 Title   : show_clusters_alignment
 Usage   : show_clusters_alignment()
 Function: 
 Returns : 
 Args    : clusters ref 

=cut 

    method show_clusters_alignment( HashRef $cluster, HashRef :$classification) {

        open( my $out, '>', $self->output_path.'/'.$self->alignment_output_file );
        
        my $meta = TCSeq::Target::Classification->meta;
 
        foreach my $break ( keys %{$cluster} ) {
            my @reads = @{$cluster->{$break}};

            say $out 'BREAK: ' . $break . "\treads:\t" . scalar @reads;
            say $out
            '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++';
            if ($classification) {
                #say Dumper $classification->{$break} unless $classification->{$break}->[0];
                
                    for my $attr ( $meta->get_all_attributes ) {
                        my $name = $attr->name;
                        say $out $name . ":" . $classification->{$break}->[0]->$name
                          if $classification->{$break}->[0]->$name;
                    }

            }
            say $out '';
            foreach my $read (@reads) {

                my $bait = $read->{bait};
                say $out ">"
                  . $bait->query->display_name . " ("
                  . length( $bait->target->seq->seq ) . "pb)";
                say $out join "\n",
                  $self->split_string( $bait->target->seq->seq );
                say $out "";

                say $out " BAIT ("
                  . $bait->seq_id . ":"
                  . $bait->start . "-"
                  . $bait->end . " "
                  . $bait->strand . ") ("
                  . $bait->query->start . " "
                  . $bait->query->end . "):\n";

                say $out join "\n", $self->pretty_alignment($bait);

                say $out "";

                
                foreach my $qstart ( sort {$a <=> $b} keys %{ $read->{bait_targets} } ) {


                    foreach my $f ( @{ $read->{bait_targets}->{$qstart} } ) {
                   #     say $out ">" 
                          #. $f->query->display_name . " ("
                          #. length( $f->target->seq->seq ) . "pb)";
                        #say $out join "\n",
                          #$self->split_string( $f->target->seq->seq );
                        #say $out "";

                        

                        say $out " PARTNER ("
                          . $f->seq_id . ":"
                          . $f->start . "-"
                          . $f->end . " "
                          . $f->strand . ") ("
                          . $f->query->start. " "
                          . $f->query->end
                          . "):\n";


                        say $out join "\n", $self->pretty_alignment($f);

                        say $out "";
                    }
                }
                        say $out "";
                        say $out "----------------------------------------------------------------------------";
 

            }

        }

        close( $out );

    }
    

=head2 classify

 Title   : classify
 Usage   : classify()
 Function: 
 Returns : A hash of rearrangements with classification
 Args    : Hashref of clustered reads by break point

=cut 

    method classify ( HashRef $alignment_cluster) {

        #Get break position;
        my ( $bait_real_chr, $bait_real_start, $bait_real_end );
        ( $bait_real_chr, $bait_real_start, $bait_real_end ) = ( $1, $2, $3 )
            if $self->bait_position =~ /(chr\S+):(\d+)-(\d+)/;

        my %classification;

        foreach my $break ( keys %{$alignment_cluster} ) {

            my @splices = split /\|/, $break;

            #next if (/chr15/ ~~ @splices[1..$#splices]);

            # Getting bait position
            my ( $alignment_bait_chr, $alignment_bait_end, $alignment_bait_strand );
            ( $alignment_bait_chr, $alignment_bait_end, $alignment_bait_strand ) = ( $1, $2, $3 )
                if $splices[0] =~ /(chr\S+)_(\d+)_(\S+)/;

            # Calculate Bait deletion size
            my $deletion_size = $bait_real_end - $alignment_bait_end;

            # Skipping if deletion size is negative
            # (maybe real but difficult to explain)
            next if $deletion_size < 0;

            # Skip bait (index 0) and get target information
            for ( my $i = 1; $i <= $#splices; $i++ ) {

                my ( $alignment_target_chr, $alignment_target_start,
                    $alignment_target_strand, $target_difference, $del_before,
                    $del_after, $bait_only );

                if ( $splices[$i] =~ /^(chr\S+)_(\d+)_([+-])_(-{0,1}\d+)/ ) {

                    (   $alignment_target_chr,    $alignment_target_start,
                        $alignment_target_strand, $target_difference
                    ) = ( $1, $2, $3, $4 );
                }
                elsif ( $splices[$i] =~ /^(chr\S+)_(\d+)_([+-])_(-{0,1}\d+)_(-{0,1}\d+)/ ) {
                    (   $alignment_target_chr, $alignment_target_start,
                        $alignment_target_strand, $del_before, $del_after
                    ) = ( $1, $2, $3, $4, $5 );
                    $bait_only         = 1;
                    $target_difference = 0;

                }
                else {
                    die "error " . $break;
                }

                # CLASSIFICATION ALGORITHM
                # ---------------------------------------------------------
                # create a hash with empty atributtes

                my $target_class = TCSeq::Target::Classification->new();

                # * Base on strand of the target related to bait
                #  - inversions
                $target_class->is_inversion(1)
                    if ( $alignment_bait_strand ne $alignment_target_strand );

                # Rearrangements
                if ( $bait_real_chr eq $alignment_target_chr ) {

                    $target_class->is_rearrangement(1);

                    # Looking for deletions of the parter if:
                    #  - Is a rearrangement
                    #  - Split only in two reads

                    if ( scalar @splices == 2 ) {

                        # calculate target_real_Start
                        my $target_real_start = $bait_real_end + $self->enzime_restriction_size;
                        my $target_deletion   = $alignment_target_start - $target_real_start;

                        if ($bait_only) {
                            $target_class->target_deletion_size($del_after);
                        }
                        elsif ( ( !$target_class->is_inversion ) && ( $target_deletion > 0 ) ) {
                            $target_class->target_deletion_size($target_deletion);
                        }
                    }

                }

                # Traslocations
                # --------------
                else {

                    $target_class->is_translocation(1);
                }

                # * Based on bait genomic position (deletions are found in the
                # genome, insertion and microhomology in the read):
                #  - Blunt
                #  - Deletion
                #  - Blunt with Insertion
                #  - Deletion with Insertion
                #  - Micromolology

                if ( $bait_real_end == $alignment_bait_end ) {

                    $target_class->bait_is_blunt(1);

                }
                else {
                    $target_class->bait_deletion_size($deletion_size);

                }

                if ( $target_difference > 0 ) {
                    $target_class->insertion_size($target_difference);

                }
                elsif ( $target_difference < 0 ) {
                    $target_class->microhomology_size( abs($target_difference) );
                }

                push( @{ $classification{$break} }, $target_class );
            }
        }

        $self->log->info("Creating Alignment output file...");
        $self->show_clusters_alignment( $alignment_cluster, \%classification );

        my %size;

        #$self->log->trace(Dumper(%classification));

        my @types = ( 'bait_deletion', 'target_deletion', 'insertion', 'microhomology' );

        foreach my $break ( keys %classification ) {

            # get only the first one
            my $target = shift @{ $classification{$break} };

            # For all

            foreach my $type (@types) {

                my $has_type  = "has_$type";
                my $type_size = $type . "_size";

                if ( $target->$has_type ) {

                    next if $target->$type_size > 1000000;

                    $size{'all'}{$type}{ $target->$type_size }++;
                }
                else {
                    $size{'all'}{$type}{0}++;
                }

                #For translocation only
                if ( $target->is_translocation ) {

                    if ( $target->$has_type ) {
                        $size{translocations}{$type}{ $target->$type_size }++;
                    }
                    else {
                        $size{translocations}{$type}{0}++;
                    }

                }

                #For rearrangement
                if ( $target->is_rearrangement ) {

                    if ( $target->$has_type ) {
                        $size{rearrangements}{$type}{ $target->$type_size }++;
                    }
                    else {
                        $size{rearrangements}{$type}{0}++;
                    }

                }
            }

        }

        my @keys = ( 'all', 'translocations', 'rearrangements' );
        my $total_reads = scalar( keys %classification );
        foreach my $key (@keys) {
            foreach my $type (@types) {

                my @aux = keys %{ $size{$key}{$type} };
                my $max = max @aux;
                next unless $max;
                my $output_file = $self->output_path . "/" . $key . "_" . $type;
                open( my $out, '>', $output_file . ".txt" );

                say $out "position\tcount\tfreq";

                my $total_reads_key = 0;
                $total_reads_key += $_ for values %{ $size{$key}->{$type} };

                for ( my $i = 1; $i <= $max; $i++ ) {

                    # print position | count | freq
                    if ( $size{$key}->{$type}->{$i} ) {
                        say $out $i . "\t"
                            . $size{$key}->{$type}->{$i} . "\t"
                            . ( ( $size{$key}->{$type}->{$i} / $total_reads ) * 100 );
                    }
                    else {
                        say $out "$i\t0\t0";
                    }

                }

                close($out);

                use Statistics::R;

                # Create a communication bridge with R and start R
                my $R = Statistics::R->new();

                # Run simple R commands
                $R->set( 'file',  $output_file . '.txt' );
                $R->set( 'title', ucfirst($type) . " in $key" );
                $R->set( 'title', ucfirst($type) . " in all events" ) if $key eq 'all';
                my $xlabel = "Distance from I-Sce1 site in bp";
                if ( $type eq 'microhomology' ) {
                    $xlabel = "Microhomology size in pb";
                }
                $R->set( 'xlabel', $xlabel );
                $R->set( 'ylabel', 'Frequency (event/total events)' );

                $R->run(q`x = read.delim(file)`);
                my $output_graphic = "$output_file.pdf";
                $R->run( qq`pdf("$output_graphic" , width=8, height=6,pointsize=1)` );
                $R->run(
                    q`barplot(x$freq,names.arg=x$position,xlab=xlabel,ylab=ylabel,main=title,col='black',axis.lty=1,cex.names=,7)`
                );
                $R->run(q`dev.off()`);

                $R->stop();

            }

        }

    }


    method _select_bait (ArrayRef $alignments, HashRef $bait, HashRef $seen, $primer_name) {
        for my $aln (@{$alignments}) {

            my $name =  $aln->query->display_name;
            next unless $name =~ /$primer_name$/;
            
            $seen->{$name}++;

            # Keep all segments that align in a bait position
            # More than one fragment from the same read can align in this
            # position. Example: A read split in 3 fragments and 2 of them 
            # are in the bait position
            push @{$bait->{$name}}, $aln;

        }
    }


    method _build_summary (HashRef $info) {
        # Generate DEBUG summary
        my @summary;

        push @summary, "\t- Total of reads: " . $info->{total_reads};
        push @summary, "\t- Total of mapped reads: " . $info->{total_reads_mapped};
        push @summary, "\t- Total of read-splits: " . $info->{total_reads_split};
        
        $info->{total_reads}||=1;
        $info->{total_reads_mapped}||=1;
        $info->{total_reads_split}||=1;
        

        push @summary,
            "\t- Total of reads with unique bait: "
          . $info->{uniq_baits} . " ("
          . ( $info->{uniq_baits} / $info->{total_reads} * 100 ) . "%)";

        push @summary,
            "\t- Total of reads with duplicated baits: "
          . $info->{duplicated_bait_reads} . " ("
          . ( $info->{duplicated_bait_reads} / $info->{total_reads} * 100 ) . "%)";

        push @summary,
            "\t- Total of reads with unique bait and with targets: "
          . $info->{uniq_bait_with_target} . " ("
          . ( $info->{uniq_bait_with_target} / $info->{total_reads} * 100 ) . "%)";
        
        push @summary,
            "\t\t - Total of reads with unique bait and with targets accepted (based on quality): "
          . $info->{uniq_bait_with_target_accepted} . " ("
          . ( $info->{uniq_bait_with_target_accepted} / $info->{total_reads} * 100 ) . "%)";

        push @summary,
            "\t- Total of reads with unique bait and no targets: "
          . $info->{uniq_bait_without_target} . " ("
          . ( $info->{uniq_bait_without_target} / $info->{total_reads} * 100 ) . "%)";

        $info->{uniq_bait_without_target}||=1;

        my $total_bait_after_break_no_target =
          $info->{bait_cut_with_deletions} + $info->{bait_blunt_cut} + $info->{bait_no_cut};

        push @summary,
            "\t\t - Bait doesn't cross breakpoint': "
          . $info->{uniq_bait_before_break} . " ("
          . ( eval{ $info->{uniq_bait_before_break} / $info->{uniq_bait_without_target} } * 100 )
          . "%)";

        push @summary,
            "\t\t - Bait with no cut (intact restriction site): "
          . $info->{bait_no_cut} . " ("
          . ( eval{ $info->{bait_no_cut} / $info->{uniq_bait_without_target} } * 100 ) . "%)";

        push @summary,
            "\t\t - Bait with blunt cut (accepted): "
          . $info->{bait_blunt_cut} . " ("
          . ( eval{ $info->{bait_blunt_cut} / $info->{uniq_bait_without_target} } * 100 ) . "%)";

        push @summary,
            "\t\t - Bait with pseudo-blunt cut (accepted): "
          . $info->{bait_pseudoblunt_cut} . " ("
          . ( eval{ $info->{bait_pseudoblunt_cut} / $info->{uniq_bait_without_target} } * 100 ) . "%)";

        push @summary,
            "\t\t - Bait cut with deletions (accepted): "
          . $info->{bait_cut_with_deletions} . " ("
          . ( eval{ $info->{bait_cut_with_deletions} / $info->{uniq_bait_without_target} } * 100 )
          . "%)";

        push @summary,
            "\t\t - Bait psedocut with deletions (accepted): "
          . $info->{bait_pseudocut_with_deletions} . " ("
          . ( eval{ $info->{bait_pseudocut_with_deletions} / $info->{uniq_bait_without_target} } * 100 )
          . "%)";

        push @summary,
          "\t- Mininum read-size (bait and target): " . $self->fragment_size;
        push @summary, "\t- Mininum MAPQ (bait and target): " . $self->min_mapq;

        push @summary,
            "\t- Total of reads sent to clustering: "
          . $info->{reads_to_clustering} . " ("
          . ( $info->{reads_to_clustering} / $info->{total_reads} * 100 ) . "%)";

        $self->log->debug( join "\n", @summary );

    }


    method _search_breakpoint_deletion_from_left_primer (
        Str $seq_id, 
        Bio::DB::Bam::AlignWrapper $this_bait, 
        HashRef $alignments_to_cluster, 
        $primer_name='left' 
    ) {
        my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };

        # Get cigar
        my $cigar_ref = $this_bait->cigar_array;
        my @deletions;
        my $ref_start = $this_bait->start;

        # get start and end of each deletion
        foreach my $entry ( @{$cigar_ref} ) {
            next if $entry->[0] =~ /[SNI]/;
            if ( $entry->[0] ne 'D' ) {
                $ref_start += $entry->[1];
            }
            else {
                push @deletions,
                    {
                    start => $ref_start,
                    end   => ( $ref_start + $entry->[1] )
                    };
                $ref_start += $entry->[1];
            }
        }

        # Check if deletion is within Isce-I site
        my $enzime_cut = 0;

        foreach my $del (@deletions) {

            # preparing key for cis translocations
            #
            my $this_strand = '+';
            $this_strand = '-' if $this_bait->strand == -1;

            my $del_size         = $del->{end} - $del->{start} - $self->enzime_restriction_size;
            my $del_before_break = ($end) - $del->{start};
            my $del_after_break  = $del->{end} - ( $end + $self->enzime_restriction_size );

            my $key =
                  $chr . '_'
                . $del->{start} . '_'
                . $this_strand . '|'
                . $chr . '_'
                . $del->{end} . '_'
                . $this_strand . '_'
                . $del_before_break . '_'
                . $del_after_break;

            if (   $del->{start} == ($end)
                && $del->{end} == ( $end + $self->enzime_restriction_size ) )
            {
                $enzime_cut = 1;
                $alignments_to_cluster->{$seq_id}->{key} = $key;
            }
            elsif ($del->{start} <= ($end)
                && $del->{end} >= ( $end + $self->enzime_restriction_size ) )
            {
                $enzime_cut = 2;
                $alignments_to_cluster->{$seq_id}->{key} = $key;
            }
            elsif (
                $del->{start} > ($end) && $del->{end} <= ( $end + $self->enzime_restriction_size )
                || $del->{start} >= ($end)
                && $del->{end} < ( $end + $self->enzime_restriction_size )

                )
            {
                $enzime_cut = 3;    #pseudo blunt
                                    # Pseudoblunt should be use the same key of normal
                                    # blunt
                my $this_key =
                      $chr . '_'
                    . $end . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . ( $end + $self->enzime_restriction_size ) . '_'
                    . $this_strand . '_0_0';

                $alignments_to_cluster->{$seq_id}->{key} = $this_key;
            }

            # Check if we have a pseudo cut
            elsif ($del->{start} > ($end)
                && $del->{start} < ( $end + $self->enzime_restriction_size ) )
            {

                $enzime_cut = 4;    #pseudo cut with deletion

                # Pseudocut should be use the same key of normal
                # cut for one of the sides
                my $this_start = ($end);

                $del_size         = $del->{end} - $this_start - $self->enzime_restriction_size;
                $del_before_break = ($end) - $this_start;
                $del_after_break  = $del->{end} - ( $end + $self->enzime_restriction_size );

                $key =
                      $chr . '_'
                    . $this_start . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . $del->{end} . '_'
                    . $this_strand . '_'
                    . $del_before_break . '_'
                    . $del_after_break;

                $alignments_to_cluster->{$seq_id}->{key} = $key;

            }
            elsif ($del->{end} > ($end)
                && $del->{end} < ( $end + $self->enzime_restriction_size ) )
            {
                $enzime_cut = 4;    #pseudo cut with deletion

                # Pseudocut should be use the same key of normal
                # cut for one of the sides
                my $this_end = ( $end + $self->enzime_restriction_size );

                my $del_size         = $this_end - $del->{start} - $self->enzime_restriction_size;
                my $del_before_break = ($end) - $del->{start};
                my $del_after_break  = $this_end - ( $end + $self->enzime_restriction_size );

                my $key =
                      $chr . '_'
                    . $del->{start} . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . $this_end . '_'
                    . $this_strand . '_'
                    . $del_before_break . '_'
                    . $del_after_break;

                $alignments_to_cluster->{$seq_id}->{key} = $key;
            }

        }

        if ( $enzime_cut == 1 ) {
            $bait_blunt_cut++;
        }
        elsif ( $enzime_cut == 2 ) {
            $bait_cut_with_deletions++;
        }
        elsif ( $enzime_cut == 3 ) {

            $bait_pseudoblunt_cut++;
        }
        elsif ( $enzime_cut == 4 ) {

            $bait_pseudocut_with_deletions++;
        }
        else {
            $bait_no_cut++;
            $invalid_reads++;
        }
    }

    
    method _search_breakpoint_deletion_from_right_primer (
        Str $seq_id, 
        Bio::DB::Bam::AlignWrapper $this_bait, 
        HashRef $alignments_to_cluster, 
        $primer_name='right' 
    ) {
        my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };

        # Get cigar
        my $cigar_ref = $this_bait->cigar_array;
        my @deletions;
        my $ref_start = $this_bait->start;

        # get start and end of each deletion
        foreach my $entry ( @{$cigar_ref} ) {
            next if $entry->[0] =~ /[SNI]/;
            if ( $entry->[0] ne 'D' ) {
                $ref_start += $entry->[1];
            }
            else {
                push @deletions,
                    {
                    start => $ref_start,
                    end   => ( $ref_start + $entry->[1] )
                    };
                $ref_start += $entry->[1];
            }
        }

        # Check if deletion is within Isce-I site
        my $enzime_cut = 0;

        foreach my $del (@deletions) {

            # preparing key for cis translocations
            #
            my $this_strand = '+';
            $this_strand = '-' if $this_bait->strand == -1;

            my $del_size         = $del->{end} - $del->{start} - $self->enzime_restriction_size;
            my $del_after_break  = ($start) - $del->{end};
            my $del_before_break = ( $start - $self->enzime_restriction_size ) - $del->{start};

            my $key =
                  $chr . '_'
                . $del->{start} . '_'
                . $this_strand . '|'
                . $chr . '_'
                . $del->{end} . '_'
                . $this_strand . '_'
                . $del_before_break . '_'
                . $del_after_break;

            if (   $del->{start} == ($start - $self->enzime_restriction_size )
                && $del->{end} == $start )
            {
                $enzime_cut = 1;
                $alignments_to_cluster->{$seq_id}->{key} = $key;

            }
            elsif ($del->{start} <= ($start - $self->enzime_restriction_size )
                && $del->{end} >= $start )
            {
                $enzime_cut = 2;
                $alignments_to_cluster->{$seq_id}->{key} = $key;

            }
            elsif (
                $del->{start} > ($start - $self->enzime_restriction_size ) && $del->{end} <= ( $start )
                || $del->{start} >= ($start - $self->enzime_restriction_size )
                && $del->{end} < ( $start )

                )
            {
                $enzime_cut = 3;    #pseudo blunt
                                    # Pseudoblunt should be use the same key of normal
                                    # blunt
                my $this_key =
                      $chr . '_'
                    . $end . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . ( $end + $self->enzime_restriction_size ) . '_'
                    . $this_strand . '_0_0';

                $alignments_to_cluster->{$seq_id}->{key} = $this_key;
            }

            # Check if we have a pseudo cut
            elsif ($del->{end} > ($start - $self->enzime_restriction_size )
                && $del->{end} < ( $start ) )
            {

                $enzime_cut = 4;    #pseudo cut with deletion

                # Pseudocut should be use the same key of normal
                # cut for one of the sides
                my $this_start = ($start);

                $del_size         = ( $this_start - $self->enzime_restriction_size ) - $del->{start} ;
                $del_before_break = 0;
                $del_after_break  =  $del_size;

                $key =
                      $chr . '_'
                    . $this_start . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . $del->{end} . '_'
                    . $this_strand . '_'
                    . $del_before_break . '_'
                    . $del_after_break;

                $alignments_to_cluster->{$seq_id}->{key} = $key;

            }
            elsif ($del->{start} > ($start - $self->enzime_restriction_size)
                && $del->{start} < ( $start  ) )
            {
                $enzime_cut = 4;    #pseudo cut with deletion

                # Pseudocut should be use the same key of normal
                # cut for one of the sides
                my $this_end = ( $start );

                my $del_size         = $del->{end} - $this_end;
                my $del_before_break = $del_size;
                my $del_after_break  = 0;

                my $key =
                      $chr . '_'
                    . $del->{start} . '_'
                    . $this_strand . '|'
                    . $chr . '_'
                    . $this_end . '_'
                    . $this_strand . '_'
                    . $del_before_break . '_'
                    . $del_after_break;

                $alignments_to_cluster->{$seq_id}->{key} = $key;
            }

        }

        if ( $enzime_cut == 1 ) {
            $bait_blunt_cut++;
        }
        elsif ( $enzime_cut == 2 ) {
            $bait_cut_with_deletions++;
        }
        elsif ( $enzime_cut == 3 ) {

            $bait_pseudoblunt_cut++;
        }
        elsif ( $enzime_cut == 4 ) {

            $bait_pseudocut_with_deletions++;
        }
        else {
            $bait_no_cut++;
            $invalid_reads++;
        }
    }


    method _define_break_in_target_only (
        Str $seq_id, 
        Bio::DB::Bam::AlignWrapper $this_bait, 
        Str $primer_name, 
        HashRef $alignments_to_cluster 
    ) {
        my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };
        if ( $primer_name =~ /left/i ) {
            # Strand doesnt matter for the reference (only)
            if ( $this_bait->end <= ( $end - 1 ) + $self->enzime_restriction_size ) {
                $uniq_bait_before_break++;
                $invalid_reads++;
            }
            # Search for reads with deletion in the breakpoint
            else {
                $self->_search_breakpoint_deletion_from_left_primer( 
                    $seq_id, 
                    $this_bait,
                    $alignments_to_cluster 
                );
            }
        }
        elsif ( $primer_name =~ /right/i ){
             # Strand doesnt matter for the reference (only)
            if ( $this_bait->start >=  ( $start  - $self->enzime_restriction_size )) {
                $uniq_bait_before_break++;
                $invalid_reads++;
            }
            # Search for reads with deletion in the breakpoint
            else {
                $self->_search_breakpoint_deletion_from_right_primer( 
                    $seq_id, 
                    $this_bait,
                    $alignments_to_cluster 
                );
            }
        }
        else {
            die "No left/right primer specified";
        }
    }


=head2 get_reliable_alignments

 Title   : get_reliable_alignments
 Usage   : get_reliable_alignments()
 Function: 
 Returns : Hashref with Complex structure
         {
         sequence_id => {
               bait => align_obj,
               bait_targets => [
                   align_obj,
                   align_obj
               ]
           }
         } 
 
 Args    : 

=cut 

    method get_reliable_alignments($primer_name) {
        $uniq_bait_without_target       = 0;
        $uniq_bait_with_target          = 0;
        $uniq_bait_with_target_accepted = 0;
        $uniq_bait_before_break         = 0;
        $bait_blunt_cut                 = 0;
        $bait_pseudoblunt_cut           = 0;
        $bait_no_cut                    = 0;
        $bait_cut_with_deletions        = 0;
        $bait_pseudocut_with_deletions  = 0;
        $invalid_reads                  = 0;
        $total_reads_mapped = 0;

        my $sam = Bio::DB::Sam->new(
            -bam          => $self->input_file,
            -fasta        => $self->fasta_file,
            -autoindex    => 1,
            -split        => 1,
            -expand_flags => 
            1
        );
        
        $self->log->debug( 'bam file: ' . $self->input_file );
        $self->log->debug( 'fasta_file: ' . $self->fasta_file );

        my ( $chr, $start, $end ) = @{ $self->_baits->{$primer_name} }{ (qw/chr start end/) };
        
        $self->log->debug( 'Filtering by bait: ' . $primer_name );

        my @alignments = $sam->get_features_by_location(
            -seq_id => $chr,
            -start  => $start,
            -end    => $end,
            -type   => 'match',
        );

        # Select bait sequence
        my %bait;
        my %seen; # Count number of reads with the same name that overlap the region    

        $self->_select_bait( \@alignments, \%bait, \%seen, $primer_name );
        
        my @uniq_bait_reads =  grep { $seen{$_} == 1} keys %seen;
        my @duplicated_bait_reads =  grep { $seen{$_} > 1} keys %seen;
        
        # Index BAM by name using a hash
        # PS: It loads all sequences into system memory. Should be used only
        # with 454 sequences or small datasets
        my %reads;
        my @all_alignments = $sam->features;
        my %total_splits_mapped;
        foreach my $aln (@all_alignments){
            push(@{$reads{$aln->query->display_name}}, $aln);
            # total mapped
            $total_splits_mapped{$aln->query->display_name}++ if $aln->qual > 0;
        }
       
        $total_reads_mapped = scalar (keys %total_splits_mapped);
       

        # $alignments_to_cluster{'sequence_id'} = {
        #       bait => align_obj,
        #       bait_targets => query_start =>  [
        #                                   align_obj,
        #                                   align_obj
        #                                  ]
        #   }
        # 
        my %alignments_to_cluster;
        
        # uncomment this line if you want to allow bait align more than one
        # time in the region
        #foreach my $seq_id ( keys %seen ) {

        # Just allow one alignment in the bait region (reads cannot split in
        # that region)
        foreach my $seq_id (@uniq_bait_reads) {
            # Keep invalid reads;
            $invalid_reads = 0;

            # Filter bait size
            $invalid_reads++
              if ( $bait{$seq_id}->[0]->query->length < $self->fragment_size
                || $bait{$seq_id}->[0]->qual < $self->min_mapq );

            # allow reads that split in only 3 pieces
            if ( scalar @{ $reads{$seq_id} } == 0 ){
                $invalid_reads++; 
            }
            
            # PROCESS BAIT ONLY ALIGNMENTS (NO SPLIT)
            # ----------------------------------------------------------------------------------
            # Check if bait split goes up to the break point and if it has
            # deletion in the enzime restriction site
            if ( scalar @{ $reads{$seq_id} } == 1 && $invalid_reads == 0) {
                $uniq_bait_without_target++;

                # access object in other variable;
                my $this_bait =  $reads{$seq_id}->[0];
                $self->_define_break_in_target_only(
                    $seq_id, 
                    $this_bait, 
                    $primer_name, 
                    \%alignments_to_cluster
                );
            }

            # PROCESS SPLITTED ALIGNMENTS
            # ----------------------------------------------------------------------------------
            my $local_bait = $bait{$seq_id}->[0];
            $alignments_to_cluster{$seq_id}{bait} = $bait{$seq_id}->[0];

            if ( scalar @{ $reads{$seq_id} } > 1 ){
            foreach my $f (@{ $reads{$seq_id} }) {
                my $read = $f->query;
                # verify if is bait sequence
                if (   $read->start == $local_bait->query->start
                    && $read->end == $local_bait->query->end
                    && $read->strand eq $local_bait->query->strand )
                {
                    # verify if bait pass througth breakpoint
                    my $condition = 1;    # condition dependent of primer direction

                    if ( $primer_name =~ /left/i ) {
                        $condition = ( $f->end > ( $end - 1 ) + $self->enzime_restriction_size );
                    }
                    elsif ( $primer_name =~ /right/i ) {
                        $condition = ( $f->start >  $start  );
                    }
                    else {
                        die "No left/right primer specified!";
                    }
                    
                    if ($condition) {
                        $invalid_reads++;
                        $bait_no_cut++;
                    }
                    next;
                }

                # filter target length
                $invalid_reads++
                    if ( $read->length < $self->fragment_size
                    || $f->qual < $self->min_mapq );

                # indexing by query position
                my $query_start;

                if ( $f->strand == 1 ) {
                    $query_start = $f->query->start;
                }
                else {
                    $query_start = length( $f->query->seq->seq ) - $f->query->start;
                }

                push
                    @{ $alignments_to_cluster{$seq_id}{bait_targets}{$query_start} },
                    $f;
            }
            } 
            # Delete invalid entries from hash
            delete $alignments_to_cluster{$seq_id} if $invalid_reads > 0;
                
            $uniq_bait_with_target_accepted++  if $invalid_reads == 0 &&
            scalar @{ $reads{$seq_id} } > 1;
            $uniq_bait_with_target++ if scalar @{ $reads{$seq_id} } > 1;
 
        }

        my $total_reads           = scalar keys %reads;
        my $total_reads_split     = scalar @all_alignments;
        my $uniq_baits            = scalar @uniq_bait_reads;
        my $duplicated_bait_reads = @duplicated_bait_reads;
        $reads_to_clustering   = scalar keys %alignments_to_cluster;
        
        $reads_to_clustering_LR += $reads_to_clustering;

        my %info = (
            total_reads_mapped             => $total_reads_mapped,
            total_reads                    => $total_reads,
            total_reads_split              => $total_reads_split,
            uniq_baits                     => $uniq_baits,
            duplicated_bait_reads          => $duplicated_bait_reads,
            reads_to_clustering            => $reads_to_clustering,
            uniq_bait_without_target       => $uniq_bait_without_target,
            uniq_bait_with_target          => $uniq_bait_with_target,
            uniq_bait_with_target_accepted => $uniq_bait_with_target_accepted,
            uniq_bait_before_break         => $uniq_bait_before_break,
            bait_blunt_cut                 => $bait_blunt_cut,
            bait_pseudoblunt_cut           => $bait_pseudoblunt_cut,
            bait_no_cut                    => $bait_no_cut,
            bait_cut_with_deletions        => $bait_cut_with_deletions,
            bait_pseudocut_with_deletions  => $bait_pseudocut_with_deletions,
        );

        $self->_build_summary(\%info);
        
        return \%alignments_to_cluster;
    }


    method generate_bedfile (HashRef $alignment_cluster) {

        open( my $out, '>', $self->output_path . '/targets.bed' );

        my $i = 0;
        foreach my $key ( keys %{$alignment_cluster} ) {
            $i++;
            my @splits        = split /\|/, $key;
            my $bait          = $splits[0];
            my $distal_target = $splits[$#splits];
            my ( $chr, $start, $strand, $primer );

            if ( $distal_target =~ /^(chr\w+)_(\d+)_([+-])/ ) {
                ( $chr, $start, $strand ) = ( $1, $2, $3 );
                $primer = 'left' if $distal_target =~ /left/;
                $primer = 'right' if $distal_target =~ /right/;
                my $color = '255,0,0';
                $color = '0,0,255' if $primer =~ /left/;
                say $out join "\t",
                    (
                    $chr, 
                    $start - 1, 
                    $start,
                    "$key", 
                    scalar( @{ $alignment_cluster->{$key} } ), 
                    $strand,
                    $start - 1, 
                    $start,
                    $color,
 
                    );
            }
        }
        close($out);

    }

    method add_target_information (HashRef $cluster) {
        my $bame         = Bio::DB::Bam->open( $self->target_file );
        my $header       = $bame->header;
        my $target_count = $header->n_targets;
        my $target_names = $header->target_name;

        $self->log->debug( 'target bam file: ' . $self->target_file );

        while ( my $align = $bame->read1 ) {
            my ( $qname, $query_start, $query_end, $query_dna );

            $qname = $align->qname;
            if ( $align->unmapped ) {
                next;
            }
            else {
                next if $align->qual < $self->min_mapq;
                if ( $cluster->{$qname} ) {
                    my $strand = '+';
                    $strand = '-' if $align->strand == -1;
                    my %h =(
                        chr => $target_names->[$align->tid],
                        start => $align->pos,
                        end => $align->calend,
                        strand => $strand,
                    );
                    push(@{$cluster->{$qname}->{real_targets}}, \%h);
                }
           }
        }
    }

    # method used to run the command
    method run {

        # Given the BAM file, get alignments to cluster.
        # Reliable reads are those which overlap this (hard coded) position by
        # default:
        # 
        # chr15:61818182-61818333
        $self->log->info("Getting reliable alignments...");
        my $aln_right = $self->get_reliable_alignments('right');
        my $aln_left = $self->get_reliable_alignments('left');
        my $reliable_alignments = { %$aln_right, %$aln_left };

        if ($self->target_file){

            $self->log->info("Adding real target information...");
            $self->add_target_information($reliable_alignments);
        }

        # print Dumper($reads_to_cluster);
        $self->log->info("Clustering...");
        my $alignments_cluster = $self->clustering_alignments($reliable_alignments);
        
        # Generating target bed file
        $self->log->info("Generating Target BED file...");
        $self->generate_bedfile($alignments_cluster);

        $self->log->info("Creating Alignment output file..."); 
        $self->show_clusters_alignment($alignments_cluster);

        #$self->log->info("Classifying aligments clusters");
        #$self->classify($alignments_cluster);
        
    }

}

class Main {
    MyApp->new_with_command->run();
}
