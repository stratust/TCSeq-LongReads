use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;

class TCSeq::App::FixBed {
    extends 'TCSeq::App'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Bio::Moose::BedIO;
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
