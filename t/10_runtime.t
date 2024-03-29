#!/usr/bin/perl -w
######################################################################
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License Version 3 or the Perl Artistic License Version 2.0.
######################################################################

use Test;

BEGIN { plan tests => 5 }
BEGIN { require "t/test_utils.pl"; }

use Make::Cache::Runtime;
ok(1);

######################################################################

{
    Make::Cache::Runtime::write
	(dir=>'test_dir',
	 key=>'make::runtime testing',
	 persist=>{testing_persistence=>1},
	 );
      ok(1);

      my $persistref = Make::Cache::Runtime::read
	  (dir=>'test_dir',
	   key=>'make::runtime testing',);
      ok($persistref && $persistref->{testing_persistence}==1);
}

{
    Make::Cache::Runtime::write
	(dir=>'test_dir',
	 key=>'make::runtime testing',
	 persist=>{testing_persistence=>2},
	 );
      ok(1);

      my $persistref = Make::Cache::Runtime::read
	  (dir=>'test_dir',
	   key=>'make::runtime testing',);
      ok($persistref && $persistref->{testing_persistence}==2);
}

######################################################################
