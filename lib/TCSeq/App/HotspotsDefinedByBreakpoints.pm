use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;

class TCSeq::App::HotspotsDefinedByBreakpoints {
    extends 'TCSeq::App';    # inherit log
    with 'TCSeq::App::Role::Index';
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
