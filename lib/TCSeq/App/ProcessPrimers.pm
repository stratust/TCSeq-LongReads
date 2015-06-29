use feature qw(say);
use MooseX::Declare;
use Method::Signatures::Modifiers;
 
class TCSeq::App::ProcessPrimers {
    extends 'TCSeq::App'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use TCSeq::LongReads;

    command_short_description q[This command is awesome];
    command_long_description q[This command is so awesome, yadda yadda yadda];

    has_file 'input_file1' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(1)],
        must_exist    => 1,
        required      => 1,
        documentation => q[Very important option!],
    );

    has_file 'input_file2' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(2)],
        must_exist    => 1,
        required      => 1,
        documentation => q[Very important option!],
    );

    option 'output_dir' => (
          is            => 'rw',
          isa           => 'Str',
          required      => '1',
          cmd_aliases   => [qw(o)],
          default => 'results',
          documentation => q['Output directory'],
    );

    option 'target_filename' => (
        is            => 'rw',
        isa           => 'Str',
        required      => '1',
        cmd_aliases   => [qw(t)],
        default       => 'targets_filtered.fasta',
        documentation => q[Name of the target file],
    );

     option 'bait_filename' => (
        is            => 'rw',
        isa           => 'Str',
        required      => '1',
        cmd_aliases   => [qw(b)],
        default       => 'baits_filtered.fasta',
        documentation => q[Name of the bait file],
    );

    option 'barcode' => (
        is            => 'rw',
        isa           => 'Str',
        required      => '1',
        default       => 'GGCCGCT',
        documentation => q[Barcode sequence (default for Philipp)],
    );
   
    option 'linkers' => (
        is       => 'rw',
        isa      => 'ArrayRef',
        required => '1',
        default  => sub {  return [
            'GCAGCGGATAACAATTTCACACAGGACGTACTGTGC', 
            'GTAAAGCTCAGTCAAGTACTGTGC'
        ];},
        documentation => q[Linkers sequences (default for Philipp)],
    );


    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $tcseq = TCSeq::LongReads->new(
            barcode => $self->barcode,
            linkers => $self->linkers,
            output_dir => $self->output_dir,
            bait_file => $self->bait_filename,
            target_file => $self->target_filename
        );

        $tcseq->annotate_primer(
            bam_file_1 => $self->input_file1,
            bam_file_2 => $self->input_file2
        );

        $self->log->warn("==> END $cmd <==");
    }
}
