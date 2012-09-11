package pgOtter;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

use Data::Dumper;
use File::Basename;
use File::Path qw( make_path );
use File::Spec;
use FindBin;
use Getopt::Long qw( :config no_ignore_case );
use Pod::Usage;
use POSIX qw( strftime :sys_wait_h );
use File::Temp qw( tempdir );
use Time::HiRes;

our $VERSION = '0.01';

=head1 pgOtter class

This documentation is meant to be for developers - if you're looking for
end-user docs, pgOtter --long-help is better option.

=head2 METHODS

=cut

=head3 new()

Object constructor, no logic in here

=cut

sub new {
    my $class = shift;
    return bless {}, $class;
}

=head3 run()

Wraps all the work that pgOtter does, starting with reading command line
arguments, config file, parsing log files and generating output.

=cut

sub run {
    my $self = shift;
    $self->read_args();
    $self->run_in_parallel( sub { $self->parse_log_file( shift ) }, $self->{ 'log_files' } );
    print Dumper( $self );
    exit;
}

=head3 parse_log_file

Handles initial parsing of single log file.

=cut

sub parse_log_file {
    my $self = shift;
    my $filename = shift;
    my $wait_time = rand() * 4 + 2;
    print "$$ : $filename : $wait_time\n";
    Time::HiRes::sleep( $wait_time );
    print "$$ : $filename : done.\n";
    return;
}

=head3 run_in_parallel

Function which runs given function, in parallel, up to given limit of jobs,
for every element in given list.

For example:

    ->run_in_parallel( sub { printf "-=>[%s]\n", shift }, [ qw( a b c ) ] );

Would run 3 printf, in parallel, each time with one of elements from
arrayref being 2nd argument to run_in_parallel().

=cut

sub run_in_parallel {
    my $self   = shift;
    my $worker = shift;
    my $args   = shift;

    my $K = $self->{ 'parallel' }->{ 'kids' } = {};
    my $D = $self->{ 'parallel' }->{ 'dead' } = [];

    my $previous_chld = $SIG{ 'CHLD' };

    $SIG{ 'CHLD' } = sub {
        # Function taken from perldoc perlipc
        my $child;
        while ( ( $child = waitpid( -1, WNOHANG ) ) > 0 ) {
            push @{ $D }, {
                'pid' => $child,
                'status' => $CHILD_ERROR,
            };
        }
    };

    my $arg_no = 0;

    srand();

    while ( 1 ) {
        printf "$$ %s : Entering loop\n", ~~localtime(time());
        my $work_count = scalar keys %{ $K };
        my $done_count = scalar @{ $D };
        last if ( 0 == $work_count ) and ( 0 == $done_count ) and ( $arg_no == scalar @{ $args } );
        if ( $self->{'jobs_limit'} > $work_count ) {
            my $child_pid = fork();
            if ($child_pid) {
                # master
                $K->{$child_pid} = 1;
                printf "$$ %s : worker ($child_pid) started for %s\n", ~~localtime(time()), $args->[$arg_no];
                $arg_no++;
                next;
            }
            # worker
            $worker->( $args->[ $arg_no ] );
            exit(0);
        }
        if ( 0 < $done_count ) {
            while ( my $kid = shift @{ $D } ) {
                printf "$$ %s : worker ($kid) ended\n", ~~localtime(time());
                delete $K->{ $kid->{'pid'} };
            }
            next;
        }
        printf "$$ %s : Before sleep\n", ~~localtime(time());
        sleep 10;    # this will be cancelled by signal, so the sleep time doesn't matter much.
        printf "$$ %s : After sleep\n", ~~localtime(time());
    }

    printf "%s : All done.\n", ~~localtime(time());

    $SIG{ 'CHLD' } = $previous_chld;
    return;
}

=head3 read_args()

Handles reading of command line options, including loading of configuration
from config file.

Merged settings (from config and command line) are stored in $self.

=cut

sub read_args {
    my $self     = shift;
    my $help     = 0;
    my $output   = '.';
    my $log_type = 'stderr';
    my $prefix   = '%t [%p]: [%l-1] ';
    my $jobs     = 1;
    my $version  = undef;

    $self->show_help_and_die()
        unless GetOptions(
        'help|h|?'     => sub { $help = 1; },
        'long-help|hh' => sub { $help = 2; },
        'config|c=s'   => sub { $self->load_config_file( $_[ 1 ] ) },
        'output-dir|o=s'      => \$output,
        'log-type|l=s'        => \$log_type,
        'log-line-prefix|p=s' => \$prefix,
        'jobs|j=i'            => \$jobs,
        'version|V'           => \$version,
        );

    if ( $help ) {
        $self->{ 'help' } = $help;
        $self->show_help_and_die();
    }
    if ( $version ) {
        printf '%s version %s%s', basename( $PROGRAM_NAME ), $VERSION, "\n";
        exit;
    }

    $self->show_help_and_die( 'Unknown log-type: %s', $log_type ) unless $log_type =~ m{\A(?:syslog|stderr|csvlog)\z};

    $self->compile_log_line_prefix_re( $prefix ) if 'csvlog' ne $log_type;

    # Upper limit of number of workers.
    $jobs = 1000 if 1000 < $jobs;

    my $real_output_dir = strftime( $output, localtime( time() ) );
    make_path( $real_output_dir ) unless -e $real_output_dir;

    $self->show_help_and_die( 'Given output (%s) is not a directory.', $real_output_dir ) unless -d $real_output_dir;
    $self->show_help_and_die( 'Given output (%s) is not writable.',    $real_output_dir ) unless -w $real_output_dir;

    $self->{ 'temp_dir' }   = tempdir( 'pgOtter.XXXXXXXXXXX', 'CLEANUP' => 1, 'TMPDIR' => 1 );
    $self->{ 'output_dir' } = $real_output_dir;
    $self->{ 'log_type' }   = $log_type;
    $self->{ 'jobs_limit' } = $jobs;

    $self->show_help_and_die( 'At least one log file has to be given.' ) if 0 == scalar @ARGV;
    for my $filename ( @ARGV ) {
        $self->show_help_and_die( 'Logfile %s is not a file.', $filename ) unless -f $filename;
        $self->show_help_and_die( 'Logfile %s is readable.',   $filename ) unless -r $filename;
    }

    $self->{ 'log_files' } = \@ARGV;
    return;
}

=head3 compile_log_line_prefix_re()

Converts given log_line_prefix value into regexp that will match this
regexp, splitting all elements into separate parts in %LAST_PAREN_MATCH
(a.k.a. %+)

If %m or %t are provided, the regexp also splits them into 6 separate
elements in %+, with keys:

=over

=item * TimeY - year
=item * TimeMo - month
=item * TimeD - day
=item * TimeH - hour
=item * TimeMi - minutes
=item * TimeS - seconds

=back

In case of %m, TimeS contains fractions.

=cut

sub compile_log_line_prefix_re {
    my $self   = shift;
    my $prefix = shift;

    my %re = (
        'a' => '\S+',
        'c' => '[a-f0-9]+\.[a-f0-9]+',
        'd' => '[a-z0-9_]*',
        'e' => '[a-f0-9]{5}',
        'h' => '\d{1,3}(?:\.\d{1,3}){3}|\[local\]|',
        'i' => 'BEGIN|COMMIT|DELETE|INSERT|ROLLBACK|SELECT|SET|SHOW|UPDATE',
        'l' => '\d+',
        'm' => '(?<TimeY>\d\d\d\d)-(?<TimeMo>\d\d)-(?<TimeD>\d\d) (?<TimeH>\d\d):(?<TimeMi>\d\d):(?<TimeS>\d\d\.\d+) (?:[A-Z]+|\+\d\d\d\d)',
        'p' => '\d+',
        'r' => '\d{1,3}(?:\.\d{1,3}){3}\(\d+\)|\[local\]|',
        's' => '\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d (?:[A-Z]+|\+\d\d\d\d)',
        't' => '(?<TimeY>\d\d\d\d)-(?<TimeMo>\d\d)-(?<TimeD>\d\d) (?<TimeH>\d\d):(?<TimeMi>\d\d):(?<TimeS>\d\d) (?:[A-Z]+|\+\d\d\d\d)',
        'u' => '[a-z0-9_]*',
        'v' => '\d+/\d+|',
        'x' => '\d+',
    );

    my @known_keys = keys %re;
    my $known_re = join '|', @known_keys;

    my @matched = ();

    # Escape characters that have special meaning in regular expressions
    $prefix =~ s/([()\[\]])/\\$1/g;

    $prefix =~ s/%($known_re)/(?<$1>$re{$1})/g;
    $self->{ 'log_line_prefix_re' } = qr{\A$prefix}o;

    return;
}

=head3 load_config_file()

Loads options from config file, and prepends them to @ARGV for further
processign by Getopt::Long.

=cut

sub load_config_file {
    my $self     = shift;
    my $filename = shift;
    my @new_args = ();
    open my $fh, '<', $filename or croak( "Cannot open $filename: $OS_ERROR\n" );
    while ( <$fh> ) {
        s/\s*\z//;
        next if '' eq $_;
        next if /\A\s*#/;
        if ( /\A\s*(-[^\s=]*)\z/ ) {

            # -v
            push @new_args, $1;
        }
        elsif ( /\A\s*(-[^\s=]*=[^'"\s]+)\z/ ) {

            # -x=123
            push @new_args, $1;
        }
        elsif ( /\A\s*(-[^\s=]*)\s+([^'"\s]+)\z/ ) {

            # -x 123
            push @new_args, $1, $2;
        }
        elsif ( /\A\s*(-[^\s=]*)(?:=|\s+)(['"])(.*)\2\z/ ) {

            # -x="123" or -x "123"
            push @new_args, $1, $3;
        }
    }
    close $fh;
    unshift @ARGV, @new_args;
    return;
}

=head3 show_help_and_die()

As name suggests, it prints help message and exits pgOtter with non-zero
status.

=cut

sub show_help_and_die {
    my $self = shift;
    my ( $format, @args ) = @_;
    if ( defined $format ) {
        $format =~ s/\s*\z/\n/;
        printf STDERR $format, @args;
    }
    my $help_level = $self->{ 'help' } // 1;
    pod2usage(
        {
            '-verbose' => $help_level,
            '-input'   => File::Spec->catfile( $FindBin::Bin, 'doc', 'pgOtter.pod' ),
            '-exitval' => 2,
        }
    );
}

1;    # End of pgOtter
