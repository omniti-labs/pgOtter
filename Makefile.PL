#!/usr/bin/env perl
use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'pgOtter',
    AUTHOR        => q{Hubert depesz Lubaczewski <depesz@depesz.com>},
    VERSION_FROM  => 'lib/pgOtter.pm',
    ABSTRACT_FROM => 'lib/pgOtter.pm',
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ( 'LICENSE' => 'bsd' )
        : () ),
    PL_FILES  => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'pgOtter-*' },
);
