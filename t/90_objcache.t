#!/usr/local/bin/perl -w
#$Revision: #1 $$Date: 2004/01/28 $$Author: wsnyder $
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2004 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
######################################################################

use Test;
use File::Path;
use File::Copy;
use Cwd;
use strict;

BEGIN { plan tests => 13 }
BEGIN { require "t/test_utils.pl"; }

chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

our $Obj_Cache = "../obj_cache --read --write";

######################################################################

our $Cache = Cwd::getcwd()."/cache";
mkpath $Cache, 0777;
$ENV{OBJ_CACHE_DIR} = $Cache;

for (my $i=0; $i<2; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    my $oc_out = run_qx("$Obj_Cache g++ -DIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Compiling test1/);
    ok(-r "test1.o");
}

{
    print "=========Dump\n";
    my $oc_out = run_qx("$Obj_Cache --dump");
    ok($oc_out =~ /test1.o .*test_dir/);
}

for (my $i=0; $i<2; $i++) {
    print "=========Read test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    my $oc_out = run_qx("$Obj_Cache g++ -DDIFFIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Object Cache Hit/);
    ok(-r "test1.o");
}

######################################################################

sub gen_file {
    my $filename = shift;
    my $datum = shift;

    my $fh = IO::File->new($filename,"w") or die;
    print $fh "extern int i; int i = $datum;\n";
    print $fh "// This is ignored: ",rand(),"\n";
    $fh->close();
}
