#!/usr/bin/perl -w
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License Version 3 or the Perl Artistic License Version 2.0.
######################################################################

use Test;
use File::Path;
use File::Copy;
use Cwd;
use strict;

BEGIN { plan tests => 12 }
BEGIN { require "t/test_utils.pl"; }

chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

our $ObjCache = "$PERL ../objcache --read --write --icecream";  #--debug
our $TestId = 96;

if (!-d "/opt/icecream/bin") {
    for (1..12) {
	skip("icecream not installed (harmless)",1);
    }
    exit 0;
}

######################################################################

$ENV{OBJCACHE_DIR} = Cwd::getcwd()."/cache";
$ENV{OBJCACHE_RUNTIME_DIR} = Cwd::getcwd()."/runtime";

for (my $i=0; $i<2; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $TestId + $i);

    my $oc_out = run_qx("$ObjCache g++ -DIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Compiling test1/);
    ok(-r "test1.o");
}

for (my $i=0; $i<2; $i++) {
    print "=========Read test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $TestId + $i);

    my $oc_out = run_qx("$ObjCache g++ -DDIFFIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Object Cache Hit/);
    ok(-r "test1.o");
}
