package pgOtter::Parser::Syslog;

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

=head1 pgOtter::Parser::Syslog class

Parses logs from PostgreSQL syslog log format.

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

    # Fix trailing space at the end of messages
    for my $level ( keys %{ $line_data->{ 'all_levels' } } ) {
        $line_data->{ $level } =~ s/\s+\z//;
    }

    my $reply   = {};
    my %key_for = (
        'a'                  => 'application_name',
        'c'                  => 'session_id',
        'd'                  => 'database_name',
        'e'                  => 'sql_state_code',
        'i'                  => 'command_tag',
        'l'                  => 'session_line_num',
        'p'                  => 'process_id',
        's'                  => 'session_start_time',
        'u'                  => 'user_name',
        'v'                  => 'virtual_transaction_id',
        'x'                  => 'transaction_id',
        'DETAIL'             => 'detail',
        'HINT'               => 'hint',
        'INTERNAL_QUERY'     => 'internal_query',
        'INTERNAL_QUERY_POS' => 'internal_query_pos',
        'CONTEXT'            => 'context',
        'QUERY_POS'          => 'query_pos',
        'LOCATION'           => 'location',
        'STATEMENT'          => 'query',
        'host'               => 'host',
    );
    for my $key ( keys %key_for ) {
        $reply->{ $key_for{ $key } } = $line_data->{ $key };
    }

    $reply->{ 'subsecond' } = 1 if defined $line_data->{ 'm' };
    $reply->{ 'log_time' }        = $line_data->{ 'm' } // $line_data->{ 't' };
    $reply->{ 'connection_from' } = $line_data->{ 'r' } // $line_data->{ 'h' };

    my $level = $line_data->{ 'base_level' };
    $reply->{ 'error_severity' } = $level;
    $reply->{ 'message' }        = $line_data->{ $level };

    my @to_delete = grep { !defined $reply->{ $_ } } keys %{ $reply };
    delete @{ $reply }{ @to_delete };

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

    # Sep 13 21:53:31 h3po4 postgres[16156]: [4-1]
    # Complex regexp below - the line with (?=[ADFJMNOS]) was generated by
    # Regexp::List for all month name abbreviations.
    my $syslog_re = qr{\A
        (?<Month>(?=[ADFJMNOS])(?:A(?:pr|ug)|J(?:u[ln]|an)|Ma[ry]|Dec|Feb|Nov|Oct|Sep))
        \s+
        (?<Day>\d{1,2})
        \s+
        (?<Hour>\d{1,2})
        :
        (?<Min>\d{1,2})
        :
        (?<Sec>\d{1,2})
        \s+
        (?<Host>\S+)
        \s+
        (?<Process>\S+)
        \[
        (?<PID>\d{1,5})
        \]
        :
        \s+
        \[ \d+ - \d+ \]
        \s+
        }xo;

    my $re = $self->prefix_re();
    croak( "There is no regexp to parse line prefix!" ) unless $re;

    my $fh = $self->fh();

    while ( 1 ) {
        my $line = <$fh>;
        last unless $line;

        unless ( $line =~ s{$syslog_re}{}o ) {
            croak( "Line doesn't match initial syslog regexp:\n$line" );
        }
        my $syslog = { %LAST_PAREN_MATCH };

        # Decode syslog-encoded special characters.
        $line =~ s/#([0-7]{3})/chr(oct($1))/ge;

        unless ( $line =~ s/$re//o ) {
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
            $self->{ 'data' }->{ 'current_level' }          = $level;
            $self->{ 'data' }->{ $level }                   = $line_data{ $level };
            $self->{ 'data' }->{ 'all_levels' }->{ $level } = 1;
            next;
        }

        $line_data{ 'all_levels' }->{ $level } = 1;
        $line_data{ 'base_level' }             = $level;
        $line_data{ 'host' }                   = $syslog->{ 'Host' };
        $line_data{ 'p' } //= $syslog->{ 'PID' };
        if (   ( !defined $line_data{ 'm' } )
            && ( !defined $line_data{ 't' } ) )
        {

            $line_data{ 't' } = $self->get_time_from_syslog( $syslog );
        }

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

=head3 get_time_from_syslog

In case log_line_prefix doesn't contain neither %t nor %m we have to take
time from syslog line prefix.

This generally works, but requires some guess-work. Not that big of a deal
usually, but still.

=cut

sub get_time_from_syslog {
    my $self         = shift;
    my $syslog       = shift;
    my $now          = time();
    my $current_year = ( localtime( $now ) )[ 5 ] + 1900;
    my $month_for    = {
        'Jan' => 1,
        'Feb' => 2,
        'Mar' => 3,
        'Apr' => 4,
        'May' => 5,
        'Jun' => 6,
        'Jul' => 7,
        'Aug' => 8,
        'Sep' => 9,
        'Oct' => 10,
        'Nov' => 11,
        'Dec' => 12,
    };
    while ( 1 ) {
        my $test_date = sprintf '%04d-%02d-%02d %02d:%02d:%02d',
            $current_year,
            $month_for->{ $syslog->{ 'Month' } },
            $syslog->{ 'Day' },
            $syslog->{ 'Hour' },
            $syslog->{ 'Min' },
            $syslog->{ 'Sec' };

        my $epoch = $self->time_to_epoch( $test_date );
        return $test_date if $epoch <= $now;
        $current_year--;
    }
}

1;
