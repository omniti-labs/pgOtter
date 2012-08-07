#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'pgOtter' ) || print "Bail out!\n";
}

diag( "Testing pgOtter $pgOtter::VERSION, Perl $], $^X" );
