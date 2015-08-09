use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;

class TCSeq::App::GetBreakPoint {
    extends 'TCSeq::App'; # inherit log
    with 'TCSeq::App::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
    use Bio::SeqIO;
    use File::Basename;
    use Progress::Any;
    use Progress::Any::Output;
    use Number::Format qw(format_number);
    use Data::Printer;
    use Bio::DB::Sam;

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
