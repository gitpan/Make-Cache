# $Revision: #6 $$Date: 2004/10/26 $$Author: ws150726 $
# DESCRIPTION: Perl ExtUtils: Type 'perl Makefile.PL' to create a Makefile for this package
#
# Copyright 2001-2004 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

require 5.005;
use ExtUtils::MakeMaker;
use Carp;

sub MY::postamble {
"
README: readme.texi
	-rm \$@
	makeinfo \$< --output \$@ --no-headers --no-validate

dist: distcheck README

## Maintainer use:
preexist:
	test ! -r \$(HOME)/src/kits/\$(DISTVNAME).tar.gz

tag:
	c4 label -d     \$(DISTNAME)_\$(VERSION_SYM) || true
	c4 label        \$(DISTNAME)_\$(VERSION_SYM)
	c4 labelsync -l \$(DISTNAME)_\$(VERSION_SYM) ...
#	cvs tag -F      \$(DISTNAME)_\$(VERSION_SYM) .

maintainer-diff:
	c4 diff     ...@\$(DISTNAME)_\$(VERSION_SYM) 

maintainer-dist: preexist dist tag
	cp \$(DISTVNAME).tar.gz \$(HOME)/src/kits
	mv \$(DISTVNAME).tar.gz \$(HOME)/backpack

maintainer-clean: distclean
	-rm README Makefile

clean::
	-rm -rf test_dir
";
}

WriteMakefile(
	      NAME      => 'Make::Cache',
	      AUTHOR	=> 'Wilson Snyder <wsnyder@wsnyder.org>',
	      ABSTRACT  => 'Caching of GCC objects and Make targets',
	      VERSION_FROM  => 'Cache.pm',
	      PREREQ_PM => {'Digest::MD5' => 1,
			    'Storable' => 1,
			},
	      EXE_FILES => [qw( objcache )],
	      'clean'	=> {FILES => qw ( ),},
	      'dist'    => {COMPRESS => 'gzip -9f',
			    SUFFIX   => '.gz', 
			    DIST_DEFAULT => 'README all tardist',
			},
	      );
