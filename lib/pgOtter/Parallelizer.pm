package pgOtter::Parallelizer;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

use POSIX qw( :sys_wait_h floor );
use IO::Select;
use Data::Dumper;
use Term::Cap;

our $VERSION = '0.01';

=head1 pgOtter::Parallelizer class

Class that provides easy (?) method for running multiple tasks in parallel, with feedback.

=head2 METHODS

=cut

=head3 new()

Object constructor, no logic in here

=cut

sub new {
    my $class = shift;
    return bless {}, $class;
}

=head3 run_in_parallel

Function which runs given worker function, in parallel, up to given limit of jobs,
for every element in given argument list.

For example:

    ->run_in_parallel(
        'worker' => sub { printf "-=>[%s]\n", shift },
        'arguments' => [ qw( a b c ) ],
        'jobs' => 3,
    );

Would run 3 printf, in parallel, each time with one of elements from
arguments arraref.

Besides those three, required, arguments, you can also provide:

=over

=item * progress - when in place, pgOtter::Parallelizer will show progress info

=item * labels - labels used when showing progress info. If not present - child PID will be used

=item * title - title for progress info screen

=back

When running in progress mode, the worker processes are supposed to:

=over

=item * at the very beginning print to stdout positive integer > 0

=item * during processing it should print to stdout current position of processing, i.e. integer between 0 and integer printed at the very beginning.

=item * each integer should be printed with new line character

=back

=cut

sub run_in_parallel {
    my $self = shift;
    $self->{ 'A' } = { @_ };

    $self->prepare_env();

    my $arg_no   = 0;
    my $last_arg = $#{ $self->{ 'A' }->{ 'arguments' } };

    srand();

    while ( 1 ) {
        my $work_count = scalar keys %{ $self->{ 'kids' } };
        my $done_count = scalar @{ $self->{ 'dead' } };
        last if ( 0 == $work_count ) and ( 0 == $done_count ) and ( $arg_no > $last_arg );

        if (   ( $arg_no <= $last_arg )
            && ( $self->{ 'A' }->{ 'jobs' } > $work_count ) )
        {
            $self->start_worker_for( $arg_no );
            $arg_no++;
            next;
        }

        if ( 0 < $done_count ) {
            while ( my $kid = shift @{ $self->{ 'dead' } } ) {
                my $pid = $kid->{ 'pid' };
                my $fh  = $self->{ 'kids' }->{ $pid }->{ 'fh' };
                close $fh;
                delete $self->{ 'kids' }->{ $pid };
                delete $self->{ 'fhs' }->{ "$fh" };
            }
            next;
        }
        $self->sleep();
    }

    $self->cleanup();

    return;
}

=head3 sleep()

Waits for either 10 seconds to pass, if needed draws progress screen, on state change.

=cut

sub sleep {
    my $self = shift;

    # this will be cancelled by signal, so the timeout time doesn't matter much.
    my @ready = $self->{ 'select' }->can_read( 5 );
    return if 0 == scalar @ready;

    for my $fh ( @ready ) {
        my $chld = $self->{ 'fhs' }->{ "$fh" };
        my $buffer;
        sysread( $fh, $buffer, 4096 );
        while ( $buffer =~ s{\A(?<pos>\d+)\r?\n}{} ) {
            if ( $chld->{ 'final' } ) {
                $chld->{ 'position' } = $LAST_PAREN_MATCH{ 'pos' };
            }
            else {
                $chld->{ 'final' }    = $LAST_PAREN_MATCH{ 'pos' };
                $chld->{ 'position' } = 0;
            }
        }
    }
    $self->update_progress_info();
    return;
}

=head3 update_progress_info

Shows progress info across all workers.

=cut

sub update_progress_info {
    my $self = shift;
    return unless $self->{ 'A' }->{ 'progress' };

    my @pids = sort { $a <=> $b } grep { defined $self->{ 'kids' }->{ $_ }->{ 'final' } } keys %{ $self->{ 'kids' } };

    for my $pid ( @pids ) {
        my $kid = $self->{ 'kids' }->{ $pid };
        $kid->{ 'progress' } = floor( 100 * $kid->{ 'position' } / $kid->{ 'final' } );
    }

    my $progress = join( ',', map { $self->{ 'kids' }->{ $_ }->{ 'progress' } } @pids );
    return if $progress eq $self->{ 'progress' };
    $self->{ 'progress' } = $progress;

    my $now = time();

    my $full_print = $self->{ 'term' }->Tputs( 'cl' ) . "Workers";
    if ( $self->{ 'A' }->{ 'title' } ) {
        $full_print .= " for '" . $self->{ 'A' }->{ 'title' } . "'";
    }
    $full_print .= ":\n\n";

    for my $pid ( @pids ) {
        my $K   = $self->{ 'kids' }->{ $pid };
        my $eta = '?';
        if ( $K->{ 'progress' } ) {
            $eta = int( ( 100 - $K->{ 'progress' } ) * ( $now - $K->{ 'started' } ) / $K->{ 'progress' } );
        }
        $full_print .= sprintf "- %s (%s):\n", $K->{ 'label' }, $K->{ 'final' };
        $full_print .= sprintf "    [%-50s] %2d%% ETA: %ss\n", "#" x ( $K->{ 'progress' } / 2 ), $K->{ 'progress' }, $eta;
    }

    syswrite( \*STDOUT, $full_print );

    return;
}

=head3 start_worker_for()

Starts single worker process for given arg_no

=cut

sub start_worker_for {
    my $self      = shift;
    my $arg_no    = shift;
    my $child_pid = open my $fh, '-|';
    if ( $child_pid ) {

        # master
        $self->{ 'kids' }->{ $child_pid } = {
            'pid'     => $child_pid,
            'arg_no'  => $arg_no,
            'fh'      => $fh,
            'started' => time(),
        };
        if ( $self->{ 'A' }->{ 'labels' } ) {
            $self->{ 'kids' }->{ $child_pid }->{ 'label' } = $self->{ 'A' }->{ 'labels' }->[ $arg_no ];
        }
        $self->{ 'kids' }->{ $child_pid }->{ 'label' } //= $child_pid;
        $self->{ 'fhs' }->{ "$fh" } = $self->{ 'kids' }->{ $child_pid };
        $self->{ 'select' }->add( $fh );

        return;
    }

    # worker
    $self->{ 'A' }->{ 'worker' }->( $self->{ 'A' }->{ 'arguments' }->[ $arg_no ] );
    exit( 0 );
}

=head3 prepare_env

Prepares "environment" for starting of parallel processing.

=cut

sub prepare_env {
    my $self = shift;
    $self->{ 'kids' }     = {};
    $self->{ 'fhs' }      = {};
    $self->{ 'dead' }     = [];
    $self->{ 'select' }   = IO::Select->new();
    $self->{ 'term' }     = Term::Cap->Tgetent();
    $self->{ 'progress' } = '';

    $self->{ 'previous_chld' } = $SIG{ 'CHLD' };

    $SIG{ 'CHLD' } = sub {

        # Function taken from perldoc perlipc
        my $child;
        while ( ( $child = waitpid( -1, WNOHANG ) ) > 0 ) {
            push @{ $self->{ 'dead' } },
                {
                'pid'    => $child,
                'status' => $CHILD_ERROR,
                };
        }
    };
    return;
}

=head3

leans various internal state variables after job is done.

=cut

sub cleanup {
    my $self = shift;
    $SIG{ 'CHLD' } = $self->{ 'previous_chld' };
    delete $self->{ 'kids' };
    delete $self->{ 'fhs' };
    delete $self->{ 'dead' };
    delete $self->{ 'previous_chld' };
    delete $self->{ 'A' };
    delete $self->{ 'select' };
    delete $self->{ 'term' };
    delete $self->{ 'progress' };
    return;
}

1;    # End of pgOtter::Parallelizer
