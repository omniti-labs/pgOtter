package pgOtter::Log_Line_Prefix;

use 5.010;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use Carp;
use English qw( -no_match_vars );

our $VERSION = '0.01';

=head1 pgOtter::Log_Line_Prefix class

Contains single function - compile_re, not exportable.

=head2 METHODS

=cut

=head3 compile_re()

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

sub compile_re {
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
    return qr{\A$prefix}o;

    return;
}

1;
