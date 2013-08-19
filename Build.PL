use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Clustericious::Admin',
    license             => 'perl',
    dist_author         => q{Brian Duggan <brian.duggan@nasa.gov>},
    dist_version_from   => 'lib/Clustericious/Admin.pm',
    configure_requires => { 'Module::Build' => 0.40 },
    requires => {
        'Test::More'            => 0,
        'Hash::Merge'           => 0,
        'Term::ANSIColor'       => 0,
        'Mojolicious'           => '2.69',
        'Clustericious::Config' => 0,
        'Clustericious::Log'    => 0,
        'Log::Log4perl::CommandLine' => 0,
      },
    add_to_cleanup      => [ 'Clustericious-Admin-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
