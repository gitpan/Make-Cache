# DESCRIPTION: Perl ExtUtils: Common routines required by package tests
#
# Copyright 2000-2009 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License Version 3 or the Perl Artistic License Version 2.0.

use IO::File;
use vars qw($PERL $GCC);

$PERL = "$^X -Iblib/arch -Iblib/lib";

`rm -rf test_dir`;
mkdir 'test_dir',0777;

if (!$ENV{HARNESS_ACTIVE}) {
    use lib "blib/lib";
    use lib "blib/arch";
    use lib "lib";
}

sub run_system {
    my $command = shift;
    # Run a system command, check errors
    print "\t$command\n";
    system "$command";
    my $status = $?;
    ($status == 0) or die "%Error: Command Failed $command, $status, stopped";
}

sub run_qx {
    my $command = shift;
    # Run a backtick system command, check errors
    print "\t$command\n";
    my $result = qx($command);
    my $status = $?;
    ($status == 0) or die "%Error: Command Failed $command, $status, stopped";
    print "\t   RESULT: $result\n";
    return $result;
}

sub wholefile {
    my $file = shift;
    my $fh = IO::File->new ($file) or die "%Error: $! $file";
    my $wholefile = join('',$fh->getlines());
    $fh->close();
    return $wholefile;
}

sub files_identical {
    my $fn1 = shift;
    my $fn2 = shift;
    my $f1 = IO::File->new ($fn1) or die "%Error: $! $fn1,";
    my $f2 = IO::File->new ($fn2) or die "%Error: $! $fn2,";
    my @l1 = $f1->getlines();
    my @l2 = $f2->getlines();
    my $nl = $#l1;  $nl = $#l2 if ($#l2 > $nl);
    for (my $l=0; $l<=$nl; $l++) {
	if (($l1[$l]||"") ne ($l2[$l]||"")) {
	    warn ("%Warning: Line ".($l+1)." mismatches; $fn1 != $fn2\n"
		  ."F1: ".($l1[$l]||"*EOF*\n")
		  ."F2: ".($l2[$l]||"*EOF*\n"));
	    return 0;
	}
    }
    return 1;
}

sub gen_file {
    my $filename = shift;
    my $datum = shift;

    my $fh = IO::File->new($filename,"w") or die;
    print $fh "extern int i; int i = $datum;\n";
    print $fh "// This is ignored: ",rand(),"\n";
    $fh->close();
}

1;
