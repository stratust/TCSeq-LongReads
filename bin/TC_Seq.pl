#!/usr/bin/env perl
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
            ],
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


class MyApp::RefineBreakpoints {
    extends 'MyApp'; # inherit log
    use MooseX::App::Command;    # important
    use MooseX::FileAttribute;
    use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
    use Data::Printer;
 
    command_short_description q[Merge breakpoints based on shear end];

    has_file 'input_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(i)],
        must_exist    => 1,
        required      => 1,
        documentation => q[Breakpoints bed file],
    );

    option 'output_dir' => (
          is            => 'rw',
          isa           => 'Str',
          required      => '1',
          cmd_aliases   => [qw(o)],
          default => 'results',
          documentation => q['Output directory'],
    );

    has_file 'output_file' => (
        traits        => ['AppOption'],
        cmd_type      => 'option',
        cmd_aliases   => [qw(f)],
        must_exist    => 0,
        required      => 1,
        default => 'targets_refined.bed',
        documentation => q[Output bed file],
    );

    method get_clusters_by_shear {
        my $in = IO::Uncompress::AnyUncompress->new($self->input_file->stringify) 
           or die "Cannot open: $AnyUncompressError\n";
        
        my %clusters;
        my %cluster_totals;
        while ( my $row = <$in> ) {
            chomp $row;
            my @F = split "\t", $row;
            my $id = $F[3];
            my $n_reads = $F[4];

            #chr15_61818338_+|chr8_61779084_+_0-left_(chr8_61779763)
            if ( $id =~ /^(chr.*)\|(chr.*)_(.*)_\((.*)\)/ ) {
                my ( $bait, $bait_target, $primer, $target ) =
                  ( $1, $2, $3, $4 );

                #say join "\t", ( $bait, $bait_target, $primer, $target );
                my $p = 'right';
                $p = 'left' if $primer =~ /left/;
                my $strand = '+';
                $strand = '-' if $bait_target =~ /\-$/;
                my $shear_key = "$target|$p|$strand";
                push @{ $clusters{$shear_key}{$n_reads} }, $row;
                $cluster_totals{$shear_key} += $n_reads;
            }
            else {
                $self->log->warn( 'Cannot find 3 positions in:' . $id );
            }
        }
        close( $in );
        
        return ( \%clusters, \%cluster_totals );

    }


    method refine_breakpoints (HashRef $clusters, HashRef $total) {

        foreach my $shear_key ( sort { $a cmp $b } keys %{$clusters} ) {
            # print breakpoint with more reads

            # Get the number of supporting reads for each brekpoint with a
            # common shear
            my @reverse_n_reads_for_this_shear =
                sort { $b <=> $a } keys %{ $clusters->{$shear_key} };

            # Get highest number of reads that support this shear
            my $highest_number_of_reads = $reverse_n_reads_for_this_shear[0];

            # Get best breapoints with highest number of shears ( could be one
            # or more )
            my @best_breakpoints = @{$clusters->{$shear_key}->{$highest_number_of_reads}};

            my $type;

            # If the shear end has more than one breakpoint
            if ( scalar @reverse_n_reads_for_this_shear > 1 ) {
                # if the there is more than one best breakpoint choose the first
                if ( scalar @best_breakpoints > 1 ) {
                    $type = '#';    # first breakpoint is choosen
                }
                else {
                    $type = '*';    # there only one breakpoint to be choosen
                }
            }

            my $row = shift @{ $clusters->{$shear_key}->{$highest_number_of_reads} };
            my @F = split "\t", $row;

            $F[3] .= $type if $type;
            $F[4] = $total->{$shear_key};
            say join "\t", @F;
        }
    }

    method run {        
        my $cmd;
        $cmd = $1 if __PACKAGE__ =~ /\:\:(.*)$/;        
        $self->log->warn("==> Starting $cmd <==");
        # Code Here
        my ( $clusters, $totals) = $self->get_clusters_by_shear();
        $self->refine_breakpoints( $clusters, $totals );
        
        $self->log->warn("==> END $cmd <==");
    }
}
   

class Main {
    import MyApp;
    MyApp->new_with_command->run();
}
