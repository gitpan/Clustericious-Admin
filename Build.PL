
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Simple parallel ssh client.",
  "dist_author" => [
    "Graham Ollis <plicease\@cpan.org>"
  ],
  "dist_name" => "Clustericious-Admin",
  "dist_version" => "0.24",
  "license" => "perl",
  "module_name" => "Clustericious::Admin",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Clone" => 0,
    "Clustericious::Config" => 0,
    "Clustericious::Log" => 0,
    "Data::Dumper" => 0,
    "Hash::Merge" => 0,
    "IPC::Open3" => 0,
    "Log::Log4perl::CommandLine" => 0,
    "Mojolicious" => "2.69",
    "Symbol" => 0,
    "perl" => "v5.10.0"
  },
  "script_files" => [
    "bin/clad"
  ],
  "test_requires" => {
    "Test::Clustericious::Config" => 0,
    "Test::More" => 0
  }
);


my %fallback_build_requires = (
  "Module::Build" => "0.3601",
  "Test::Clustericious::Config" => 0,
  "Test::More" => 0
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
