#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'App::Base' ) || print "Bail out!\n";
}

diag( "Testing App::Base $App::Base::VERSION, Perl $], $^X" );
