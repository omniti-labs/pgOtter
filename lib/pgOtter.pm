package pgOtter;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

use Getopt::Long qw( :config no_ignore_case );
use Data::Dumper;
use Pod::Usage;
use FindBin;
use File::Basename;
use File::Spec;

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
    print "All looks good.\n";
    exit;
}

=head3 read_args()

Handles reading of command line options, including loading of configuration
from config file.

Merged settings (from config and command line) are stored in $self.

=cut

sub read_args {
    my $self = shift;
    my $help = 0;
    my $output;
    my $log_type;
    my $prefix;
    my $jobs;
    my $version;

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

    printf "%-10s : %s.\n", "output",   $output   // "<UNDEF>";
    printf "%-10s : %s.\n", "log_type", $log_type // "<UNDEF>";
    printf "%-10s : %s.\n", "prefix",   $prefix   // "<UNDEF>";
    printf "%-10s : %s.\n", "jobs",     $jobs     // "<UNDEF>";
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
            -verbose => $help_level,
            -input   => File::Spec->catfile( $FindBin::Bin, 'doc', 'pgOtter.pod' ),
            -exitval => 2,
        }
    );
}

1;    # End of pgOtter
