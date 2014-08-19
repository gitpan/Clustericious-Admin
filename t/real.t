use strict;
use warnings;
use Test::More;
use File::Spec;
use Clustericious::Admin;
use Test::Clustericious::Config;

plan skip_all => 'set CLUSTERICIOUS_ADMIN_TEST_REAL to enable this test'
  unless $ENV{CLUSTERICIOUS_ADMIN_TEST_REAL};

plan tests => 2;

my $dir;

subtest prep => sub {
  plan tests => 2;
  $dir = create_directory_ok 'foo';
  create_config_ok 'Clad', { clusters => { foo => [ 'localhost'] } };
};

subtest go => sub {
  Clustericious::Admin->run({}, 'foo', "touch $dir/foo.txt");
  my $fn = File::Spec->catfile($dir, 'foo.txt');
  ok -e $fn, "file $fn exists";
};
