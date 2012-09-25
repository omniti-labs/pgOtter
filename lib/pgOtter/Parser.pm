package pgOtter::Parser;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

our $VERSION = '0.01';

=head1 pgOtter::Parser class

Base class for all pgOtter::Parser::* classes, which implement parsing of specific log formats

=head2 METHODS

=cut

=head3 new()

Object constructor. No logic in here.

=cut

sub new {
    my $class = shift;
    return bless {}, $class;
}

=head3 fh()

Accessor to set/get filehandle which should be used for reading logs.

=cut

sub fh {
    my $self = shift;
    if ( 0 < scalar @_ ) {
        $self->{ 'fh' } = shift;
    }
    return $self->{ 'fh' };
}

=head3 prefix_re()

Accessor to set/get regular expression to match line prefix (log_line_prefix from postgresql.conf).

=cut

sub prefix_re {
    my $self = shift;
    if ( 0 < scalar @_ ) {
        $self->{ 'prefix_re' } = shift;
    }
    return $self->{ 'prefix_re' };
}

=head3 next_line()

Returns next parsed log line from logs.

This method is overwritten in all classes inheriting pgOtter::Parser, but it
is here to provide single point of documentation.

Returned value is hashref. Actually returned rows depend on log type and (in
case of syslog and stderr, log_line_prefix), but full list of possible keys
is:

=over

=item * log_time

=item * user_name

=item * database_name

=item * process_id

=item * connection_from

=item * session_id

=item * session_line_num

=item * command_tag

=item * session_start_time

=item * virtual_transaction_id

=item * transaction_id

=item * error_severity

=item * sql_state_code

=item * message

=item * detail

=item * hint

=item * internal_query

=item * internal_query_pos

=item * context

=item * query

=item * query_pos

=item * location

=item * application_name

=back

These fields come straight from parsing log_line_prefix (one letter keys), or their meaning is as in CSV-format described in documentation.

Additionally, there are additional fields computed:

=over

=item * host - database server host name (only in syslog)

=item * subsecond - is the log_time/epoch withsubsecond precision (it is
possible that the time with subsecond precision will be aaaa-bb-cc
dd:ee:ff.000 - so checking for non-zero fraction will not work). Encoded as
1 (true) or undef (false).

=back

=cut

sub next_line {
    croak( "It should never happen - this method is overriden in subclasses." );
}

=head3 all_lines

Helper function, useful mainly in tests - returns arrayref of hashrefs,
where each element (hashref) represents single line in logs.

Format of hashrefs is the same as in next_line().

DO NOT USE IT FOR ANYTHING EXCEPT SMALL TESTS AS IT WILL CONSUME LOTS OF
MEMORY.

=cut

sub all_lines {
    my $self = shift;
    my @reply;
    while ( my $row = $self->next_line() ) {
        push @reply, $row;
    }
    return \@reply;
}

1;
