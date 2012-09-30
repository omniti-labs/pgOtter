#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec;
use Test::More tests => 126;
use Test::Exception;
use File::Temp qw( tempdir );
use File::Spec;

use pgOtter::MultiWriter;

my $temp_dir = tempdir( 'CLEANUP' => 1 );
my $writer;
lives_ok { $writer = pgOtter::MultiWriter->new( 10 ); } "object creation";

my %d = ();

for my $f ( 1, 2, 3 ) {
    my $data = "$f\n";
    $d{ $f } = $data;
    lives_ok { $writer->write( File::Spec->catfile( $temp_dir, $f ), $data ); } "Writing data before sync ($f)";
}

for my $f ( 1, 2, 3 ) {
    ok( !-f File::Spec->catfile( $temp_dir, $f ), "File #$f doesn't yet exist." );
}

lives_ok { $writer->sync } "Calling sync";

for my $f ( 1, 2, 3 ) {
    ok( -f File::Spec->catfile( $temp_dir, $f ), "File #$f exists, after sync" );
}

for my $f ( 1 .. 20 ) {
    my $data = "$f\n";
    $d{ $f } .= $data;
    lives_ok { $writer->write( File::Spec->catfile( $temp_dir, $f ), $data ); } "Writing data stage 2 ($f)";
}

lives_ok { $writer->sync } "Calling sync (#2)";

is( scalar keys %{ $writer->{ 'buffers' } }, scalar keys %{ $writer->{ 'fhs' } }, 'Sanity check #1' );
is( scalar keys %{ $writer->{ 'buffers' } }, scalar @{ $writer->{ 'fh_queue' } }, 'Sanity check #2' );
is( scalar @{ $writer->{ 'fh_queue' } },     1,                                   'Only one buffer/filehandle left' );

for my $f ( 1 .. 30 ) {
    my $data = "$f\n";
    $d{ $f } .= $data;
    lives_ok { $writer->write( File::Spec->catfile( $temp_dir, $f ), $data ); } "Writing data stage 3 ($f)";
}

lives_ok { undef $writer } 'DESTROYing writer';

for my $f ( 1 .. 20 ) {
    my $filename = File::Spec->catfile( $temp_dir, $f );
    ok( -f $filename, "File #$f exists, after DESTROY" );
    my $fh;
    lives_ok { open $fh, '<', $filename } "Opening file $filename for reading";
    my $got = join '', <$fh>;
    close $fh;
    is( $got, $d{ $f }, "Data in file $f as expected." );
}

exit
