#!perl -T

use Test::More tests => 3;

BEGIN {
    use_ok( 'pgOtter' )                  || print "Bail out!\n";
    use_ok( 'pgOtter::Parser' )          || print "Bail out!\n";
    use_ok( 'pgOtter::Log_Line_Prefix' ) || print "Bail out!\n";
}

diag( "Testing pgOtter $pgOtter::VERSION, Perl $], $^X" );
