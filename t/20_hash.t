#!/usr/bin/perl -w
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2008 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
######################################################################

use Test;
BEGIN { plan tests => (1+4+4+2) }
BEGIN { require "t/test_utils.pl"; }

use Make::Cache::Hash;
ok(1);

######################################################################

{
    my $fn = "t/20_hash.d";
    my $href = Make::Cache::Hash::dfile_read(filename=>$fn);
    ok(1);

    #use Data::Dumper; print Dumper($href);
    ok($href->{a}{c} && $href->{a}{d} && $href->{a}{e});
    ok($href->{b}{c} && $href->{b}{d});
    ok($href->{$fn}{c} && $href->{$fn}{d} && $href->{$fn}{e});
}

{
    my $hash = Make::Cache::Hash::hash(filenames=>["t/20_hash.d"],);
    ok(1);
    print "$hash\n";
    ok($hash eq "bd75dab08de59f8f85331755783b78a9");

    my $hash2 = Make::Cache::Hash::hash(text=>["foo"]);
    print "$hash2\n";
    ok($hash2 eq "acbd18db4cc2f85cedef654fccc4a4d8");

    Make::Cache::Hash::clear_cache();
    ok(1);
}

{
    my $new = Make::Cache::Hash::newest(filenames=>["t/20_hash.d"],);
    ok($new);

    my $punt = Make::Cache::Hash::newest(filenames=>["t/not_found"],);
    ok(!defined $punt);
}

######################################################################
