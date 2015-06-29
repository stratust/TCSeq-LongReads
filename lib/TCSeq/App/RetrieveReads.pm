use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
 
class TCSeq::App::RetrieveReads {
    extends 'TCSeq::App'; # inherit log
    with 'TCSeq::App::Role::Index';
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
