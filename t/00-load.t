#!perl -T

use Test::More tests => 9;

BEGIN {
    use_ok( 'pgOtter' )                  || print "Bail out on pgOtter\n";
    use_ok( 'pgOtter::Log_Line_Prefix' ) || print "Bail out on pgOtter::Log_Line_Prefix\n";
    use_ok( 'pgOtter::MultiWriter' )     || print "Bail out on pgOtter::MultiWriter\n";
    use_ok( 'pgOtter::Parallelizer' )    || print "Bail out on pgOtter::Parallelizer\n";
    use_ok( 'pgOtter::Parser' )          || print "Bail out on pgOtter::Parser\n";
    use_ok( 'pgOtter::Parser::Csvlog' )  || print "Bail out on pgOtter::Parser::Csvlog\n";
    use_ok( 'pgOtter::Parser::Stderr' )  || print "Bail out on pgOtter::Parser::Stderr\n";
    use_ok( 'pgOtter::Parser::Syslog' )  || print "Bail out on pgOtter::Parser::Syslog\n";
    use_ok( 'pgOtter::Stage1' )          || print "Bail out on pgOtter::Stage1\n";
}

diag( "Testing pgOtter $pgOtter::VERSION, Perl $], $^X" );
