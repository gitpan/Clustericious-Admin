#!perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'Clustericious::Admin' ) || print "Bail out!
";
}

diag( "Testing Clustericious::Admin $Clustericious::Admin::VERSION, Perl $], $^X" );
