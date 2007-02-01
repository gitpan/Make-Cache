#!/usr/bin/perl -w
#$Id: 96_icecream.t 31185 2007-02-01 14:40:37Z wsnyder $
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2007 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
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
