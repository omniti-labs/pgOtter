package pgOtter::Parser::Stderr;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

use base qw( pgOtter::Parser );

our $VERSION = '0.01';

=head1 pgOtter::Parser::Stderr class

Parses logs from PostgreSQL stderr log format.

=head2 METHODS

=cut

=head3 next_line()

Returns next parsed log line from logs.

Full documentation is in pgOtter::Parser perldoc.

=cut

sub next_line {
    my $self = shift;

    my $line_data = $self->get_line_data();
    return unless $line_data;
    my $reply   = {};
    my %key_for = (
        'a' => 'application_name',
        'c' => 'session_id',
        'd' => 'database_name',
        'e' => 'sql_state_code',
        'i' => 'command_tag',
        'l' => 'session_line_num',
        'p' => 'process_id',
        's' => 'session_start_time',
        'u' => 'user_name',
        'v' => 'virtual_transaction_id',
        'x' => 'transaction_id',
    );
    for my $key ( keys %key_for ) {
        $reply->{ $key_for{ $key } } = $line_data->{ $key };
    }

    $reply->{ 'subsecond' } = 1 if defined $line_data->{ 'm' };
    $reply->{ 'log_time' }        = $line_data->{ 'm' } // $line_data->{ 't' };
    $reply->{ 'connection_from' } = $line_data->{ 'r' } // $line_data->{ 'h' };

    for my $key ( qw( detail hint internal_query internal_query_pos context query_pos location ) ) {
        $reply->{ $key } = $line_data->{ uc $key };
    }
    $reply->{ 'query' } = $line_data->{ 'STATEMENT' };

    my $level = $line_data->{ 'base_level' };
    $reply->{ 'error_severity' } = $level;
    $reply->{ 'message' }        = $line_data->{ $level };

    my @to_delete = grep { !defined $reply->{ $_ } } keys %{ $reply };
    delete @{ $reply }{ @to_delete };

    for my $value ( values %{ $reply } ) {
        $value =~ s/\s*\z//;
    }

    return $reply;
}

=head3 get_line_data

Parses single logged "line".

This can actually be multiple text lines in case of multiline queries or
logged lines that require HINT/CONTEXT/STATEMENT/.. addons.

=cut

sub get_line_data {
    my $self = shift;

    $self->{ 'data' } //= {};

    my $reply = undef;

    my $re = $self->prefix_re();
    croak( "There is no regexp to parse line prefix!" ) unless $re;

    my $fh = $self->fh();

    while ( 1 ) {
        my $line = <$fh>;
        last unless $line;
        if ( $line !~ s/$re//o ) {
            my $level = $self->{ 'data' }->{ 'current_level' };
            unless ( $level ) {
                croak( "line without prefix, but we never got beginning of log message?!\n: " . $line );
            }
            $self->{ 'data' }->{ $level } .= $line;
            next;
        }
        my %line_data = %LAST_PAREN_MATCH;

        croak( "Logged line contains unexpected data after prefix:\n$line" ) unless $line =~ s{\A(?<level>[A-Z0-9]+):\s\s}{};
        my $level = $LAST_PAREN_MATCH{ 'level' };

        $line_data{ 'current_level' } = $level;
        $line_data{ $level } = $line;

        # if level is none of the below listed, it's something like
        # HINT/CONTEXT/STATEMENT, so we need to procedd further
        if ( $level !~ m{ \A (?: DEBUG[1-5] | INFO | NOTICE | WARNING | ERROR | LOG | FATAL | PANIC ) \z }x ) {
            $self->{ 'data' }->{ 'current_level' } = $level;
            $self->{ 'data' }->{ $level } = $line_data{ $level };
            next;
        }

        $line_data{ 'base_level' } = $level;
        if ( 0 == scalar keys %{ $self->{ 'data' } } ) {

            # This is first ever line in log, data is empty
            $self->{ 'data' } = \%line_data;
            next;
        }
        $reply = $self->{ 'data' };
        $self->{ 'data' } = \%line_data;
        last;
    }
    if (   ( !$reply )
        && ( 0 < scalar keys %{ $self->{ 'data' } } ) )
    {
        $reply = $self->{ 'data' };
        $self->{ 'data' } = {};
    }
    return $reply;
}

1;
