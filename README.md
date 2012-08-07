pgOtter
=======

This is PostgreSQL query log analyzer.

It's purpose is to have as many features as possible, but make it possible
to analyze, even huge, logfiles on modest machines.

Usage
-----

While there is Makefile.PL, and you actually can proceed using standard Perl
installation approach:

    perl Makefile.PL
    make
    make test
    make install

and then using simply "pgOtter" program, you can also simply keep the
fetched pgOtter directory someplace, and use without full "installation".

In such case, run:

    .../pgOtter/bin/pgOtter

Of course you will need some options - you will get list of options by
running

    pgOtter --help

or, if you really want more information:

    pgOtter --long-help

