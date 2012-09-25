package pgOtter::Parser::Csvlog;

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

=head1 pgOtter::Parser::Csvlog class

Parses logs from PostgreSQL CSVLOG log format.

=head2 METHODS

=cut

=head3 next_line()

Returns next parsed log line from logs.

Full documentation is in pgOtter::Parser perldoc.

=cut

sub next_line {
    my $self = shift;

    my $fields = $self->extract_fields();
    return unless $fields;

    my $output = {};
    @{ $output }{
        qw(
            log_time                user_name         database_name
            process_id              connection_from   session_id
            session_line_num        command_tag       session_start_time
            virtual_transaction_id  transaction_id    error_severity
            sql_state_code          message           detail
            hint                    internal_query    internal_query_pos
            context                 query             query_pos
            location                application_name
            )
        }
        = @{ $fields };
    $output->{ 'subsecond' } = 1;

    return $output;
}

=head3 extract_fields()

Actually parses single record from log.

This can span multiple lines, if any value contains literal new line character.

Returned value is arrayref with 23 elements. Value quotes are removed, and
quote character inside values are properly de-escaped.

=cut

sub extract_fields {
    my $self = shift;

    my $fh = $self->fh();

    my @fields;
    my $buffer = '';

    while ( 1 ) {
        my $line = <$fh>;
        return unless defined $line;
        $buffer .= $line;
        while (
            $buffer =~ s{
                \A
                (
                [^",]*                    # Not quoted field
                |
                "(?:[^"]|"")*"            # " quoted field, with " escaped to ""
                )
                (,|\r?\n)
            }{$2}ox
            )
        {
            my $value = $1;
            if ( $value =~ s/\A"// ) {
                $value =~ s/""/"/g;
                $value =~ s/"\z//;
            }
            push @fields, $value;
            $buffer =~ s/\A,//;
            last if $buffer =~ m{\A\r?\n\z};
        }
        if ( $buffer =~ m{\A\r?\n\z} ) {
            last if 23 == scalar @fields;
            next if 23 > scalar @fields;
            croak( "Too many fields extracted when parsing line:\n$line" );
        }
    }
    return \@fields;
}

1;
