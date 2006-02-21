#!/usr/bin/perl -w
#$Id: 90_objcache.t 14521 2006-02-21 18:52:32Z wsnyder $
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2006 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
######################################################################

use Test;
use File::Path;
use File::Copy;
use Cwd;
use strict;

BEGIN { plan tests => 21 }
BEGIN { require "t/test_utils.pl"; }

mkdir 'test_dir/obj_dir',0777;
chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

our $ObjCache = "$PERL ../objcache --read --write";

######################################################################

$ENV{OBJCACHE_DIR} = Cwd::getcwd()."/cache";
$ENV{OBJCACHE_RUNTIME_DIR} = Cwd::getcwd()."/runtime";

for (my $i=0; $i<3; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/* ../test_dir/obj_dir/*"));
    gen_file("test1.cpp", $i);

    my $objdir = ($i==2)?"obj_dir/":"";
    my $oc_out = run_qx("$ObjCache g++ -DIGNORED test1.cpp -c -o ${objdir}test1.o");
    ok($oc_out);
    ok($oc_out =~ /Compiling test1/);
    ok(-r "${objdir}test1.o");
}

{
    print "=========Dump\n";
    my $oc_out = run_qx("$ObjCache --dump");
    ok($oc_out =~ /test1.o .*test_dir/);
}

for (my $i=0; $i<3; $i++) {
    print "=========Read test $i\n";
    unlink(glob("../test_dir/* ../test_dir/obj_dir/*"));
    gen_file("test1.cpp", $i);

    my $objdir = ($i==2)?"obj_dir/":"";
    my $oc_out = run_qx("$ObjCache g++ -DDIFFIGNORED test1.cpp -c -o ${objdir}test1.o");
    ok($oc_out);
    ok($oc_out =~ /Object Cache Hit/);
    ok(-r "${objdir}test1.o");
}

{
    print "=========Jobs test\n";
    local $ENV{OBJCACHE_HOSTS} = "a:b:c";
    my $oc_out = run_qx("$ObjCache --jobs");
    ok($oc_out);
    ok($oc_out =~ /^3/);
}
