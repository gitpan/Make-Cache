#!/usr/bin/perl -w
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2009 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
######################################################################

use Test;
use File::Path;
use File::Copy;
use Cwd;
use strict;

BEGIN { plan tests => 27 }
BEGIN { require "t/test_utils.pl"; }

mkdir 'test_dir/obj_dir',0777;
chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

our $ObjCache = "$PERL ../objcache --read --write";

######################################################################

$ENV{OBJCACHE_DIR} = Cwd::getcwd()."/cache";
$ENV{OBJCACHE_RUNTIME_DIR} = Cwd::getcwd()."/runtime";

for (my $i=0; $i<4; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/* ../test_dir/obj_dir/*"));
    my ($oc_out,$objdir) = test_iter($i);
    ok($oc_out);
    ok($oc_out =~ /Compiling test1/);
    ok(-r "${objdir}test1.o");
}

{
    print "=========Dump\n";
    my $oc_out = run_qx("$ObjCache --dump");
    ok($oc_out =~ /test1.o .*test_dir/);
}

for (my $i=0; $i<4; $i++) {
    print "=========Read test $i\n";
    unlink(glob("../test_dir/* ../test_dir/obj_dir/*"));
    my ($oc_out,$objdir) = test_iter($i);
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

sub test_iter {
    my $i = shift;
    my $objdir = "";
    my $opt = "-O1";
    if ($i==0) {
	gen_file("test1.cpp", 0);
    } elsif ($i==1) {
	gen_file("test1.cpp", 1);
    } elsif ($i==2) {
	$objdir = "obj_dir/";
	gen_file("test1.cpp", 2);
    } elsif ($i==3) {
	$opt = "-O2";
	gen_file("test1.cpp", 0); # Repeat
    } else {
	die "%Error: Bad i $i\n";
    }
    return ((run_qx("$ObjCache g++ -DIGNORED test1.cpp ${opt} -c -o ${objdir}test1.o")),
	    $objdir);
}
