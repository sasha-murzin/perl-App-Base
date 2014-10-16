use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;

WriteMakefile(
    NAME                => 'App::Base',
    AUTHOR              => q{Binary.com <binary@cpan.org>},
    VERSION_FROM        => 'lib/App/Base.pm',
    ABSTRACT_FROM       => 'lib/App/Base.pm',
    LICENSE             => 'perl',
    PL_FILES            => {},
    PREREQ_PM => {
    },
    TEST_REQUIRES => {
        'Test::More' => 0.94,
    },
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 6.64,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'App-Base-*' },
    META_MERGE => {
        no_index => {
            file => 'README.pod'
        },
        resources => {

            license    => 'http://dev.perl.org/licenses/',
        },
    },
);
