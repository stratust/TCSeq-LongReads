#!/usr/bin/env perl
#
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


class MyApp::Process_Primers {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use lib "lib";
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


    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        
        # Code Here
        my $tcseq = TCSeq::LongReads->new(
            barcode => 'GGCCGCT',
            linkers => [ 
                'GCAGCGGATAACAATTTCACACAGGACGTACTGTGC', 
                'GTAAAGCTCAGTCAAGTACTGTGC' 
            ]
        );

        $tcseq->annotate_primer(
            bam_file_1 => $self->input_file1,
            bam_file_2 => $self->input_file2
        );

        $self->log->warn("==> END $cmd <==");
    }
}


class Main {
    import MyApp;
    MyApp->new_with_command->run();
}
