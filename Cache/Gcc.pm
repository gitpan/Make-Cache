#!/usr/local/bin/perl -w
#$Revision: #5 $$Date: 2004/02/11 $$Author: wsnyder $
######################################################################
#
# This program is Copyright 2002-2004 by Wilson Snyder.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either the GNU General Public License or the
# Perl Artistic License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#                                                                           
######################################################################

package Make::Cache::Gcc;

use Make::Cache::Obj;
use Carp;
use strict;

use vars qw(@ISA $Debug);

@ISA=qw(Make::Cache::Obj);
*Debug = \$Make::Cache::Obj::Debug;  	# "Import" $Debug

our $VERSION = '1.011';

#######################################################################
## Methods that superclasses are likely to override

sub is_legal_cmd {
    my $self = shift;
    my @cmds = @_;
    (my $prog = $cmds[0]) =~ s!.*/!!;
    return "gnu" if ($prog eq "g++" || $prog eq "gcc");
    return "ghs" if ($prog eq "cxppc");
    return undef;
}

#######################################################################
# Overrides of base classes

sub parse_cmds {
    my $self = shift;
    # Parse the program and arguments.  Die if parsing trouble
    # Else, load self with necessary info
    
    my @params = $self->cmds_lcl;

    my $wholeParams = join(' ',@params);
    $params[0] or die "objcache: %Error: Not passed any program on command line\n";
    my $ccType = $self->is_legal_cmd(@params)
	or die "objcache: %Error: Unknown program $params[0] (Or use --help)\n";

    # Parse cc's arguments
    my $lastsw;
    my @tgtfiles;
    my @srcfiles;

    # It's faster and safer to use the output of the preprocessor
    # as that prevents files that change in the middle of the compile
    # run from messing things up
    $self->{use_preproc_output} = 1 unless $ccType eq "ghs";

    my $cmd = shift @params;
    $self->flags_lcl($cmd);
    $self->{cmds_lcl_cpp_run} = [$cmd];	# Commands for preprocessor
    $self->{cmds_lcl_cex_run} = [$cmd];	# Commands for compiler
    my $dbo;
    foreach my $sw (@params) {
	if ($sw =~ /^-/) {
	    $lastsw = $sw;
	    $dbo=1 if ($sw eq "-G" || $sw eq "-g") && $ccType eq "ghs";
	    if ($sw ne "-o") {
		push @{$self->{cmds_lcl_cpp_run}}, $sw;
	    }
	    if ($sw ne "-o"
		&& $sw ne "-MD"
		&& $sw ne "-MMD") {
		push @{$self->{cmds_lcl_cex_run}}, $sw;
	    }
	    if ($sw !~ /^-[DUI]/) {	# Skip defines and include path switches in hashing
		$self->flags_lcl($sw);
	    }
	} elsif ($lastsw eq "-o") {
	    push @tgtfiles, $sw;
	    $self->flags_lcl($sw);
	} else {
	    push @srcfiles, $sw;
	    push @{$self->{cmds_lcl_cpp_run}}, $sw;
	    $self->flags_lcl($sw);
	}
    }
    push @{$self->{cmds_lcl_cpp_run}}, "-E";

    if ($Debug) {
	print "   OrigCmd: ",join(' ',$self->cmds_lcl),"\n";
	print "   CppCmd:  ",join(' ',@{$self->{cmds_lcl_cpp_run}}),"\n";
	print "   CexeCmd: ",join(' ',@{$self->{cmds_lcl_cex_run}}),"\n";
	print "   HashCmd: ",join(' ',$self->flags_lcl),"\n";
	print "   HashGbl: ",join(' ',$self->flags_gbl),"\n";
    }

    (defined $srcfiles[0]) or die "objcache: %Error: No source filename: $wholeParams\n";

    my $no_tgts = !defined $tgtfiles[0];

    foreach my $src (@srcfiles) {
	($src =~ /\.(c|cc|cpp)$/)
	    or die "objcache: %Error: Strange source filename: $src: $wholeParams\n";
	$self->deps_lcl($src);
	if ($no_tgts) {  # Gcc presumes given baz/foo.c that output goes to PWD/foo.o
	    ((my $ofile = $src) =~ s/\.(c|cc|cpp)$/.o/)
		or die "objcache: %Error: Strange source filename: $src: $wholeParams\n";
	    $ofile =~ s%.*[\/\\]%%;	# Output goes to PWD, not source's location
	    push @tgtfiles, $ofile;
	}
	if ($dbo) {  # Ghs presumes given baz/foo.c that output goes to PWD/foo.o
	    ((my $dbofile = $tgtfiles[0]) =~ s/\.(o)$/.dbo/)
		or die "objcache: %Error: Strange .o filename: $tgtfiles[0]: $wholeParams\n";
	    # Output goes to same dir as .o file
	    push @tgtfiles, $dbofile;
	    #?? $dbo = 0;
	}
    }

    foreach my $tgt (@tgtfiles) {
	$self->tgts_lcl($tgt);
    }
}

sub preproc_cmds {
    my $self = shift;

    my @cmds = @{$self->{cmds_lcl_cpp_run}};
    return @cmds;
}

sub compile_cmds {
    my $self = shift;
    my @cmds;
    if ($self->{use_preproc_output}) {
	@cmds = @{$self->{cmds_lcl_cex_run}};
	push @cmds, $self->temp_filename;
	my @tgt = $self->tgts_lcl;
	push @cmds, "-o", $tgt[0];	# User may not have specified a -o, and don't want to go to tempfile
    } else {
	@cmds = @{$self->{cmds_lcl}};
    }
    return @cmds;
}

######################################################################
1;
__END__

=pod

=head1 NAME

Make::Cache::Gcc - ObjCache specialization for GCC/G++

=head1 DESCRIPTION

Make::Cache::Gcc is a superclass of Make::Cache::Obj with methods
specialized for parsing GCC command lines.

Make::Cache::Gcc will run a GCC in pre-process mode to create a single
source file.  This file is then hashed with Make::Cache::Obj, and hits
detected. On misses, GCC is run again to create the targets.

=head1 FUNCTIONS

See C<Make::Cache::Obj>

=head1 SEE ALSO

C<objcache>, C<Make::Cache::Obj>

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################