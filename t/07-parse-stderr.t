#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;
use Test::More tests => 7;
use Test::Deep;
use Test::Exception;
use Data::Dumper;

use pgOtter::Parser::Stderr;
use pgOtter::Log_Line_Prefix;

my $test_file = File::Spec->catfile( 't', 'logs', 'test.stderr.log' );

my $re;
lives_ok { $re = pgOtter::Log_Line_Prefix::compile_re( 'a[%a] u[%u] d[%d] r[%r] h[%h] p[%p] t[%t] m[%m] i[%i] e[%e] c[%c] l[%l] s[%s] v[%v] x[%x] ' ) } 'Log line prefix compilation';

my $fh;
lives_ok { open $fh, '<', $test_file or die "Canot open $test_file: $!" } 'Opening test file';

my $parser;
lives_ok { $parser = pgOtter::Parser::Stderr->new(); } "Object creation";

lives_ok { $parser->prefix_re( $re ) } "Passing log_line_prefix regexp";

lives_ok { $parser->fh( $fh ) } "Passing filehandle";

my $got;
lives_ok { $got = $parser->all_lines() } 'Getting data';

my $expected = expected();

cmp_deeply( $got, $expected, 'Lines parsed correctly from stderr log' );

if ( $ENV{ 'DEBUG_TESTS' } ) {
    $Data::Dumper::Sortkeys = 1;
    print STDERR 'got: ' . Dumper( $got );
}
exit;

sub expected {
    return [
        {
            'application_name' => 'psql',
            'command_tag'      => 'SELECT',
            'connection_from'  => '[local]',
            'context'          => 'SQL statement "SELECT b()"
	PL/pgSQL function a() line 1 at PERFORM',
            'database_name'          => 'depesz',
            'error_severity'         => 'LOG',
            'log_time'               => '2012-09-13 21:49:37.840 CEST',
            'message'                => '[logged line]',
            'process_id'             => '15444',
            'query'                  => 'select a();',
            'session_id'             => '505238d0.3c54',
            'session_line_num'       => '3',
            'session_start_time'     => '2012-09-13 21:49:36 CEST',
            'sql_state_code'         => '00000',
            'subsecond'              => 1,
            'transaction_id'         => '0',
            'user_name'              => 'depesz',
            'virtual_transaction_id' => '2/2'
        },
        {
            'application_name'       => 'psql',
            'command_tag'            => 'SELECT',
            'connection_from'        => '[local]',
            'database_name'          => 'depesz',
            'error_severity'         => 'LOG',
            'log_time'               => '2012-09-13 21:49:37.841 CEST',
            'message'                => 'duration: 1.662 ms  statement: select a();',
            'process_id'             => '15444',
            'session_id'             => '505238d0.3c54',
            'session_line_num'       => '6',
            'session_start_time'     => '2012-09-13 21:49:36 CEST',
            'sql_state_code'         => '00000',
            'subsecond'              => 1,
            'transaction_id'         => '0',
            'user_name'              => 'depesz',
            'virtual_transaction_id' => '2/0'
        }
    ];
}
