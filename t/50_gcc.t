#!/usr/bin/perl -w
#$Id: 50_gcc.t 14521 2006-02-21 18:52:32Z wsnyder $
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

BEGIN { plan tests => 22 }
BEGIN { require "t/test_utils.pl"; }

use Make::Cache::Gcc;
ok(1);

$Make::Cache::Gcc::Debug=1 if !$ENV{HARNESS_ACTIVE};

chdir "test_dir";
(Cwd::getcwd() =~ /test_dir/) or die;

######################################################################

$ENV{OBJCACHE_DIR} = Cwd::getcwd()."/cache";
$ENV{OBJCACHE_RUNTIME_DIR} = Cwd::getcwd()."/runtime";

for (my $i=0; $i<2; $i++) {
    print "=========Write test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);
    Make::Cache::Obj->clear_hash_cache;

    my $mc = Make::Cache::Gcc->new (dir=>$ENV{OBJCACHE_DIR},);
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
    my $mc = Make::Cache::Gcc->new (dir=>$ENV{OBJCACHE_DIR},);
    $mc->dump;
}

for (my $i=0; $i<2; $i++) {
    Make::Cache::clear_hash_cache;
    print "=========Read test $i\n";
    unlink(glob("../test_dir/*"));
    gen_file("test1.cpp", $i);
    Make::Cache::Obj->clear_hash_cache;

    system("g++","-DDIFFIGNORED", "test1.cpp","-c","-o","test1.exp");
    ok(-r "test1.exp");

    my $mc = Make::Cache::Gcc->new (dir=>$ENV{OBJCACHE_DIR},);
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
