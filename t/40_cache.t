#!/usr/local/bin/perl -w
#$Revision: #4 $$Date: 2004/02/10 $$Author: wsnyder $
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2004 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
######################################################################

use Test;
use File::Path;
use Cwd;
use strict;

BEGIN { plan tests => 13 }
BEGIN { require "t/test_utils.pl"; }

use Make::Cache;
ok(1);


######################################################################

our $Cache = Cwd::getcwd()."/test_dir/cache";
mkpath $Cache, 0777;

for (my $i=0; $i<2; $i++) {
    gen_file("test_dir/test1.in", $i);
    gen_file("test_dir/test1.out", $i);

    my $mc = Make::Cache->new (dir=>$Cache);
    ok(1);
    $mc->cmds_lcl("tcc");
    $mc->cmds_lcl("cmd2");
    $mc->flags_lcl("tcc");
    $mc->deps_lcl("t/40_cache.t");
    $mc->deps_lcl(Cwd::getcwd()."/test_dir/test1.in");
    $mc->tgts_lcl(Cwd::getcwd()."/test_dir/test1.out");
    $mc->write();
    ok(1);
}

{
    Make::Cache::clear_hash_cache;
    my $mc = Make::Cache->new (dir=>$Cache);

    $mc->dump();
    ok(1);

    $mc->clean();
    ok(1);
}

for (my $i=0; $i<2; $i++) {
    gen_file("test_dir/test1.in", $i);
    unlink("test_dir/test1.out");

    my $mc = Make::Cache->new (dir=>$Cache);
    $mc->cmds_lcl("tcc");
    $mc->cmds_lcl("cmd2_not_hashed");
    $mc->flags_lcl("tcc");
    $mc->tgts_lcl(Cwd::getcwd()."/test_dir/test1.out");

    my $hit = $mc->find_hit();
    ok($hit);

    my $ok = $hit->restore if $hit;
    ok($ok);
    ok(check_file("test_dir/test1.out", $i));
}


if (0) {
    my $mc = Make::Cache->new (dir=>'/usr/local/common/lib/objcache/fc');
    $mc->dump();
    ok(1);
}

######################################################################

sub gen_file {
    my $filename = shift;
    my $datum = shift;

    my $fh = IO::File->new($filename,"w") or die;
    print $fh "$filename = $datum\n";
    $fh->close();
    Make::Cache::clear_hash_cache;
}

sub check_file {
    my $filename = shift;
    my $datum = shift;

    if (!-r $filename) {
	warn "%Error: File missing: $filename\n";
	return undef;
    }
    my $wholefile = wholefile($filename);
    my $exp = "$filename = $datum\n";
    if ($wholefile ne $exp) {
	warn "%Error: File mismatch: $filename\nGOT: $wholefile\nEXP: $exp\n";
	return undef;
    }
    return 1;
}
