use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
 
class TCSeq::App::FilterBreakpoints {
    extends 'TCSeq::App';    # inherit log
    with 'TCSeq::App::Role::Index';
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);

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
