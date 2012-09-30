package pgOtter::Stage1;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );
use Data::Dumper;
use File::Spec;
use File::Path qw( make_path );
use pgOtter::MultiWriter;
use Storable qw( freeze );

our $VERSION = '0.01';

=head1 pgOtter::Stage1 class

First stage of log parsing - based on data from pgOtter::Parser::* it splits
data to files based on session/pid, puts errors/fatals separately
- generally splits log files into multiple files in temp_dir.

=head2 METHODS

=cut

=head3 new()

Object constructor. Takes two arguments:

=over

=item * worker number - assumed to be non-negative integer. Should correlate
with order of files handled

=item * temp directory path

=back

All files will be created in $temp_dir/stage-1

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{ 'worker' } = shift;
    my $temp_dir = shift;
    $self->{ 'temp_dir' } = File::Spec->catdir( $temp_dir, 'stage-1' );
    make_path( $self->{ 'temp_dir' } ) unless -e $self->{ 'temp_dir' };
    $self->{ 'writer' } = pgOtter::MultiWriter->new();
    return $self;
}

=head3 handle_line()

Splits data from logs to multiple outputs, depending on backend and message type

=cut

sub handle_line {
    my $self       = shift;
    my $line       = shift;
    my %separately = (
        'FATAL'   => 1,
        'PANIC'   => 1,
        'ERROR'   => 1,
        'WARNING' => 1,
        'LOG'     => 0,
    );
    $self->{ 'x' }->{ $line->{ 'error_severity' } }++;
    return unless exists $separately{ $line->{ 'error_severity' } };

    my $output_data = $self->make_output( $line );

    if ( $separately{ $line->{ 'error_severity' } } ) {
        $self->{ 'writer' }->write( $self->{ 'temp_dir' } . sprintf( '/level-%s-%d', $line->{ 'error_severity' }, $self->{ 'worker' } ), $output_data );
        return;
    }
    my $backend_id = $line->{ 'process_id' } || $line->{ 'session_id' };
    $self->{ 'writer' }->write( $self->{ 'temp_dir' } . sprintf( '/backend-%s-%d', $backend_id, $self->{ 'worker' } ), $output_data );
    return;
}

=head3 make_output()

Converts structure to stream of bytes, in such a way that it will *not*
contain literal enter character (\n) - except for one \n at the end of data.

It is doneby using Storable to freeze structure to stream of bytes, and
later escaping \n (and \) to \XX, where X is hexadecimal ascii code of \n
and/or \.

=cut

sub make_output {
    my $self    = shift;
    my $data    = shift;
    my $stream  = freeze( $data );
    my %replace = (
        "\n" => "\\0A",
        "\\" => "\\5C"
    );
    $stream =~ s/([\n\\])/$replace{$1}/g;
    return $stream . "\n";
}

1;
