#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;
use Test::More tests => 6;
use Test::Deep;
use Test::Exception;
use Data::Dumper;

use pgOtter::Parser::Stderr;
use pgOtter::Log_Line_Prefix;

my $re;
lives_ok { $re = pgOtter::Log_Line_Prefix::compile_re( '%m [%r] [%p]: [%l-1] user=%u,db=%d,e=%e ' ) } 'Log line prefix compilation';

my $parser;
lives_ok { $parser = pgOtter::Parser::Stderr->new(); } "Object creation";

lives_ok { $parser->prefix_re( $re ) } "Passing log_line_prefix regexp";

lives_ok { $parser->fh( \*DATA ) } "Passing filehandle";

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
            'connection_from'  => '',
            'database_name'    => '[unknown]',
            'error_severity'   => 'LOG',
            'log_time'         => '2012-09-10 15:15:03.572 UTC',
            'message'          => 'connection received: host=10.101.138.51 port=51608',
            'process_id'       => '8294',
            'session_line_num' => '1',
            'sql_state_code'   => '00000',
            'subsecond'        => 1,
            'user_name'        => '[unknown]',
        },
    ];
}

__DATA__
2012-09-10 15:15:03.572 UTC [] [8294]: [1-1] user=[unknown],db=[unknown],e=00000 LOG:  connection received: host=10.101.138.51 port=51608
