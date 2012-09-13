#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;
use Test::More tests => 5;
use Test::Deep;
use Test::Exception;

use pgOtter::Parser::Csvlog;

my $test_file = File::Spec->catfile( 't', 'logs', 'test.csvlog.log' );

my $fh;
lives_ok { open $fh, '<', $test_file or die "Canot open $test_file: $!" } 'Opening test file';

my $parser;
lives_ok { $parser = pgOtter::Parser::Csvlog->new(); } "Object creation";

lives_ok { $parser->fh( $fh ) } "Object creation";

my $got;
lives_ok { $got = $parser->all_lines() } 'Getting data';

my $expected = expected();

cmp_deeply( $got, $expected, 'Lines parsed correctly from csv log' );

exit;

sub expected {
    return
        [
          {
            'application_name' => 'psql',
            'command_tag' => 'SELECT',
            'connection_from' => '[local]',
            'context' => 'SQL statement "SELECT b()"
PL/pgSQL function a() line 1 at PERFORM',
            'database_name' => 'depesz',
            'detail' => '',
            'epoch' => '1347565872.642',
            'error_severity' => 'LOG',
            'hint' => '',
            'internal_query' => '',
            'internal_query_pos' => '',
            'location' => '',
            'log_time' => '2012-09-13 21:51:12.642 CEST',
            'message' => '[logged line]',
            'process_id' => '15673',
            'query' => 'select a();',
            'query_pos' => '',
            'session_id' => '5052392f.3d39',
            'session_line_num' => '3',
            'session_start_time' => '2012-09-13 21:51:11 CEST',
            'sql_state_code' => '00000',
            'subsecond' => 1,
            'transaction_id' => '0',
            'user_name' => 'depesz',
            'virtual_transaction_id' => '2/2'
          },
          {
            'application_name' => 'psql',
            'command_tag' => 'SELECT',
            'connection_from' => '[local]',
            'context' => '',
            'database_name' => 'depesz',
            'detail' => '',
            'epoch' => '1347565872.642',
            'error_severity' => 'LOG',
            'hint' => '',
            'internal_query' => '',
            'internal_query_pos' => '',
            'location' => '',
            'log_time' => '2012-09-13 21:51:12.642 CEST',
            'message' => 'duration: 1.561 ms  statement: select a();',
            'process_id' => '15673',
            'query' => '',
            'query_pos' => '',
            'session_id' => '5052392f.3d39',
            'session_line_num' => '4',
            'session_start_time' => '2012-09-13 21:51:11 CEST',
            'sql_state_code' => '00000',
            'subsecond' => 1,
            'transaction_id' => '0',
            'user_name' => 'depesz',
            'virtual_transaction_id' => '2/0'
          }
        ];
    }
