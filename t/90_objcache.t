#!/usr/bin/perl -w
#$Revision: #5 $$Date: 2004/06/21 $$Author: ws150726 $
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

BEGIN { plan tests => 15 }
BEGIN { require "t/test_utils.pl"; }

chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

our $ObjCache = "$PERL ../objcache --read --write";

######################################################################

$ENV{OBJCACHE_DIR} = Cwd::getcwd()."/cache";
$ENV{OBJCACHE_RUNTIME_DIR} = Cwd::getcwd()."/runtime";

for (my $i=0; $i<2; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    my $oc_out = run_qx("$ObjCache g++ -DIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Compiling test1/);
    ok(-r "test1.o");
}

{
    print "=========Dump\n";
    my $oc_out = run_qx("$ObjCache --dump");
    ok($oc_out =~ /test1.o .*test_dir/);
}

for (my $i=0; $i<2; $i++) {
    print "=========Read test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    my $oc_out = run_qx("$ObjCache g++ -DDIFFIGNORED test1.cpp -c -o test1.o");
    ok($oc_out);
    ok($oc_out =~ /Object Cache Hit/);
    ok(-r "test1.o");
}

{
    print "=========Jobs test\n";
    local $ENV{OBJCACHE_HOSTS} = "a:b:c";
    my $oc_out = run_qx("$ObjCache --jobs");
    ok($oc_out);
    ok($oc_out =~ /^3/);
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
