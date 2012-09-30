package pgOtter::MultiWriter;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

our $VERSION = '0.01';

=head1 pgOtter::MultiWriter class

Class for writing multiple files with buffer to make the writing happen less
often, and to make it possible to write to thousands of files.

=head2 METHODS

=cut

=head3 new()

Object constructor.

If there is an argument it's treated as byte limit of data to be stored in
buffers, before ->sync() method is auto-called.

If there is no argument, pgOtter::MultiWriter assumes the limit is
10,000,000 - i.e. 10 megabytes.

=cut

sub new {
    my $class = shift;
    my $limit = shift || 10000000;
    my $self  = bless {}, $class;
    $self->{ 'limit' }    = $limit;
    $self->{ 'length' }   = 0;
    $self->{ 'fhs' }      = {};
    $self->{ 'fh_queue' } = [];
    return $self;
}

=head3 write()

Usual work-horse - method called by external code to write data.

It takes two arguments:

=over

=item * filename of file to write to

=item * data to write

=back

write() will store the data in buffer, and if the total (across all files)
buffer size is larger than limit assumed on object creation time - it will
call sync().

=cut

sub write {
    my $self          = shift;
    my $filename      = shift;
    my $data_to_write = shift;
    $self->{ 'buffers' }->{ $filename } //= '';
    $self->{ 'buffers' }->{ $filename } .= $data_to_write;
    $self->{ 'length' } += length( $data_to_write );
    $self->sync() if $self->{ 'length' } > $self->{ 'limit' };
    return;
}

=head3 sync()

Writes all buffers to actual files. If necessary opens or closes
filehandles, but generally tries to keep open/close to minimum.

=cut

sub sync {
    my $self = shift;
    my %drop = ();
    while ( my ( $filename, $buffer ) = each %{ $self->{ 'buffers' } } ) {
        if ( 0 == length $buffer ) {
            $drop{ $filename } = 1;
            next;
        }
        my $fh = $self->get_fh_for( $filename );
        print $fh $buffer;
        $self->{ 'length' } -= length( $buffer );
        $self->{ 'buffers' }->{ $filename } = '';
    }

    return if 0 == scalar keys %drop;

    # Remove buffers/filehandles that had empty buffers at the beginning of this sync
    $self->{ 'fh_queue' } = [ grep { !$drop{ $_ } } @{ $self->{ 'fh_queue' } } ];
    for my $key ( keys %drop ) {
        delete $self->{ 'buffers' }->{ $key };
        my $fh = delete $self->{ 'fhs' }->{ $key };
        close $fh;
    }

    return;
}

=head3 get_fh_for()

Returns filehandle for writing to given file.

If no such filehandle exists - it opens new one.

If there are too many opened already - it will close some previous
filehandle.

=cut

sub get_fh_for {
    my $self     = shift;
    my $filename = shift;

    if ( !$self->{ 'fhs' }->{ $filename } ) {
        if ( 100 < scalar @{ $self->{ 'fh_queue' } } ) {
            my $fn_to_close = shift @{ $self->{ 'fh_queue' } };
            my $close_fh    = delete $self->{ 'fhs' }->{ $filename };
            close $close_fh if defined $close_fh;
        }
        open my $fh, '>>', $filename or croak( "Cannot write to $filename: $OS_ERROR\n" );
        push @{ $self->{ 'fh_queue' } }, $filename;
        $self->{ 'fhs' }->{ $filename } = $fh;
    }
    return $self->{ 'fhs' }->{ $filename };
}

=head3 DESTROY()

Object destructor. Calls sync() to write all unsaved data to files.

=cut

sub DESTROY {
    my $self = shift;
    $self->sync();
    return;
}

1;
