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

BEGIN { plan tests => 22 }
BEGIN { require "t/test_utils.pl"; }

use Make::Cache::Gcc;
ok(1);

$Make::Cache::Gcc::Debug=1 if !$ENV{HARNESS_ACTIVE};

chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

######################################################################

our $Cache = Cwd::getcwd()."/cache";
mkpath $Cache, 0777;

for (my $i=0; $i<2; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    my $mc = Make::Cache::Gcc->new (dir=>$Cache,);
    ok(1);

    $mc->cmds_lcl("g++","-DIGNORED", "test1.cpp","-c","-o","test1.o");
    $mc->parse_cmds;
    $mc->preproc;
    ok(1);

    my $hitref = $mc->find_hit();
    ok(!defined $hitref);   # Cache is empty
    ok($mc->tgts_missing);

    $mc->execute;
    ok(-r "test1.o");

    my $miss = $mc->tgts_missing;
    print "Missing: $miss\n" if $miss;
    ok(!$miss);

    $mc->encache();

    ok(1);
}

{
    print "=========Dump\n";
    my $mc = Make::Cache::Gcc->new (dir=>$Cache,);
    $mc->dump;
}

for (my $i=0; $i<2; $i++) {
    Make::Cache::clear_hash_cache;
    print "=========Read test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);

    system("g++","-DDIFFIGNORED", "test1.cpp","-c","-o","test1.exp");
    ok(-r "test1.exp");

    my $mc = Make::Cache::Gcc->new (dir=>$Cache,);
    $mc->cmds_lcl("g++","-DDIFFIGNORED", "test1.cpp","-c","-o","test1.o");
    $mc->parse_cmds;

    $mc->preproc;
    my $hit = $mc->find_hit();
    ok($hit);
    $hit->restore if $hit;

    ok(-r "test1.o");
}

print "=========Cleanup\n";
my @i = glob("*.i .*.i");
ok($#i == -1);

######################################################################

sub gen_file {
    my $filename = shift;
    my $datum = shift;

    my $fh = IO::File->new($filename,"w") or die;
    print $fh "extern int i; int i = $datum;\n";
    print $fh "// This is ignored: ",rand(),"\n";
    $fh->close();
    Make::Cache::Obj->clear_hash_cache;
}
