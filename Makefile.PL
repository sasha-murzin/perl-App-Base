use 5.010;
use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;

die "OS is not supported\n" if $^O eq 'MSWin32';

WriteMakefile(
    NAME          => 'App::Base',
    AUTHOR        => q{Binary.com <binary@cpan.org>},
    VERSION_FROM  => 'lib/App/Base.pm',
    ABSTRACT_FROM => 'lib/App/Base.pm',
    LICENSE       => 'perl',
    PL_FILES      => {},
    PREREQ_PM     => {
        'File::Flock::Tiny'    => 0,
        'List::Util'           => 0,
        'Moose'                => 0,
        'Moose::Role'          => 0,
        'MooseX::Types'        => 0,
        'namespace::autoclean' => 0,
        'Path::Tiny'           => 0,
        'Text::Reform'         => 0,
        'Try::Tiny'            => 0,
    },
    TEST_REQUIRES => {
        'File::Slurp'        => 0,
        'Test::Exit'         => 0,
        'Test::More'         => 0.94,
        'Test::Most'         => 0.21,
        'Test::FailWarnings' => 0,
        'Text::Trim'         => 0,
        'Test::Warn'         => 0,
    },
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 6.64, },
    dist               => { COMPRESS              => 'gzip -9f', SUFFIX => 'gz', },
    clean              => { FILES                 => 'App-Base-*' },
    META_MERGE => {
        requires  => { perl => 5.010 },
        resources => {
            homepage   => 'https://github.com/binary-com/perl-App-Base',
            bugtracker => 'https://github.com/binary-com/perl-App-Base/issues',
            repository => 'git://github.com/binary-com/perl-App-Base',
            license    => 'http://dev.perl.org/licenses/',
        },
        x_contributors => [
            'Calum Halcrow',
            'Chris Travers',
            'Fayland Lam <fayland@gmail.com>',
            'Jean-Yves Sireau',
            'Kaveh Mousavi Zamani',
            'Matt Miller',
            'Nick Marden',
            'Pavel Shaydo <zwon@cpan.org>',
            'Tee Shuwn Yuan',
        ],
    },
);
