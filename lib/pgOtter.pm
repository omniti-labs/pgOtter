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
use pgOtter::Log_Line_Prefix;
use pgOtter::Stage1;
use pgOtter::Parallelizer;
use IO::Uncompress::AnyUncompress qw( $AnyUncompressError );

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
    $self->load_parser();
    my $runner = pgOtter::Parallelizer->new();
    $runner->run_in_parallel(
        'worker'    => sub { $self->parse_log_file( @_ ) },
        'arguments' => $self->{ 'log_files' },
        'labels'    => $self->{ 'log_files' },
        'jobs'      => $self->{ 'jobs_limit' },
        'progress' => $self->{ 'quiet' } ? undef : 1,
        'title' => 'Log parsing',
    );

    print Dumper( $self );
    exit;
}

=head3 load_parser()

Loads parser class based on chosen log_type

=cut

sub load_parser {
    my $self     = shift;
    my $class    = sprintf 'pgOtter::Parser::%s', ucfirst( lc( $self->{ 'log_type' } ) );
    my $filename = $class . '.pm';
    $filename =~ s{::}{/}g;

    require $filename;
    $self->{ 'parser' } = $class->new();

    if ( 'csvlog' ne $self->{ 'log_type' } ) {
        my $prefix_re = pgOtter::Log_Line_Prefix::compile_re( $self->{ 'log_line_prefix' } );
        $self->{ 'parser' }->prefix_re( $prefix_re );
    }
    return;
}

=head3 parse_log_file

Handles initial parsing of single log file.

=cut

sub parse_log_file {
    my $self     = shift;
    my $arg_no   = shift;
    my $filename = shift;

    open my $raw_fh, '<', $filename or croak( "Cannot read from $filename: $OS_ERROR" );
    my $previous = 0;

    my $fh = IO::Uncompress::AnyUncompress->new( $raw_fh ) or croak( "anyuncompress failed: $AnyUncompressError\n" );

    printf "%s\n", ( stat( $filename ) )[ 7 ];

    $self->{ 'parser' }->fh( $fh );

    my $stage1 = pgOtter::Stage1->new( $arg_no, $self->{ 'temp_dir' } );

    while ( my $line = $self->{ 'parser' }->next_line() ) {
        my $new_pos = tell( $raw_fh );
        printf "%s\n", $new_pos if $new_pos != $previous;
        $previous = $new_pos;
        $stage1->handle_line( $line );
    }
    close $fh;

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
    my $quiet    = 0;

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
        'quiet|q'             => \$quiet,
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
    $self->show_help_and_die( 'For stderr logs, log_line_prefix has to contain %p or %c.' ) if $log_type eq 'stderr' && $prefix !~ /%[pc]/;

    # Upper limit of number of workers.
    $jobs = 1000 if 1000 < $jobs;

    my $real_output_dir = strftime( $output, localtime( time() ) );
    make_path( $real_output_dir ) unless -e $real_output_dir;

    $self->show_help_and_die( 'Given output (%s) is not a directory.', $real_output_dir ) unless -d $real_output_dir;
    $self->show_help_and_die( 'Given output (%s) is not writable.',    $real_output_dir ) unless -w $real_output_dir;

    $self->{ 'temp_dir' }        = tempdir( 'pgOtter.XXXXXXXXXXX', 'CLEANUP' => 0, 'TMPDIR' => 1 );
    $self->{ 'output_dir' }      = $real_output_dir;
    $self->{ 'log_type' }        = $log_type;
    $self->{ 'log_line_prefix' } = $prefix;
    $self->{ 'jobs_limit' }      = $jobs;
    $self->{ 'quiet' }           = $quiet;

    $self->show_help_and_die( 'At least one log file has to be given.' ) if 0 == scalar @ARGV;
    for my $filename ( @ARGV ) {
        $self->show_help_and_die( 'Logfile %s is not a file.', $filename ) unless -f $filename;
        $self->show_help_and_die( 'Logfile %s is readable.',   $filename ) unless -r $filename;
    }

    $self->{ 'log_files' } = \@ARGV;
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
