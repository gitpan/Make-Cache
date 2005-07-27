#$Revision: 4089 $$Date: 2005-07-27 09:55:32 -0400 (Wed, 27 Jul 2005) $$Author: wsnyder $
######################################################################
#
# This program is Copyright 2002-2005 by Wilson Snyder.
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

package Make::Cache::Obj;

use Sys::Hostname;
use POSIX qw(:sys_wait_h);

use Make::Cache::Hash;
use Make::Cache::Runtime;
use Make::Cache;
use Digest::MD5;
use Cwd;
use Carp;
use strict;

use vars qw(@ISA $Debug);

@ISA=qw(Make::Cache);
*Debug = \$Make::Cache::Debug;  	# "Import" $Debug

our $VERSION = '1.030';

our $Cc_Running_Lock;
our $Temp_Filename;
(our $Hostname = hostname()) =~ s/\..*$//;

$ENV{HOME} or die "%Error: HOME not set in environment,";

END {
    cc_running_unlock();
    unlink $Temp_Filename if $Temp_Filename && !$Debug;
}

use constant One_Compile_Filename => ($ENV{TEMP}||$ENV{TMP}||"/tmp")."/.objcache_one_cc";  # Keep on the local machine/build so doesn't conflict with other remote jobs
use constant One_Delay_Override => (10*60);	# Seconds of compiler time to ignore one_compile file after

######################################################################
#### Creators

sub new {
    my $class = shift;
    my $self = $class->SUPER::new
	(
	 remote_hosts => [],	# Array of hosts to choose between
	 min_remote_runtime => undef,	# Num secs runtime must exceed to be worth remote shell.
	 temp_filename => undef,
	 ok_include_regexps => [],
	 edit_line_refs => {},
	 nfs_wait => 4,	# Seconds to wait for targets to appear
	 distcc => undef,
	 icecream => undef,
	 @_,
	 );
    bless $self, ref($class)||$class;
}

######################################################################
# Accessors

sub distcc { return $_[0]->{distcc}; }

sub icecream { return $_[0]->{icecream}; }

sub temp_filename {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
	$self->{temp_filename} = $value;
	$Temp_Filename = $value;  # So we can unlink it in END
    }
    return $self->{temp_filename};
}

sub ok_include_regexps {
    my $self = shift;
    push @{$self->{ok_include_regexps}}, @_;
}

######################################################################
# Preprocessing

sub deps_fixed_digest {
    my $self = shift;
    # Overrides Make::Class method
    if (!defined $self->{_deps_fixed_digest}) {
	croak "%Error: preproc not called, or didn't create a hash,";
    }
    return $self->{_deps_fixed_digest};
}

sub preproc {
    my $self = shift;

    # Make a temporary file for the convenience of exec_preproc's.
    # This can't be in /tmp alas because remoting requires it to be visible.
    # We use the same extension as the original filename because some
    # compile drivers use that to determine what language it is!
    my $ext = "i";
    my @srcs = $self->deps_lcl;
    $ext = $1 if $srcs[0] =~ /^.*\.([^.]+)$/;
    $self->temp_filename(".objcache_$$.$ext");

    # Execute the preprocessor
    $self->run_stdout($self->temp_filename, $self->preproc_cmds);

    # Compute hash on preprocessed results
    $self->{_deps_fixed_digest} = $self->_preproc_hash;
}

sub parse_cmds {}

sub _preproc_hash {
    my $self = shift;

    # Hash the important parts of the command used to generate the output
    my $md5 = Digest::MD5->new;
    foreach my $cmd ($self->flags_gbl) {
	$md5->add($cmd);
    }
    
    # Hash the generated preprocess output
    my $wholefile;
    {
	my $fh = IO::File->new($self->temp_filename)
	    or die "objcache: %Error: Preprocessor failed: ".join(' ',$self->preproc_cmds)."\n";
	local $/; undef $/;
	$wholefile = <$fh>;	# Much faster then reading a line.
	$fh->close;
    }

    if (keys %{$self->{edit_line_refs}}) {
	my $origfile = $wholefile;
	while (my ($key,$val) = each %{$self->{edit_line_refs}}) {
	    print "Replace $key $val\n" if $Debug;
	    $wholefile =~ s!^(\#l?i?n?e?\s+\d+\s+) \"${key} ([^\"]+) \" (.*$ )  !$1\"${val}$2\"$3!mgx;
        }
	if ($origfile ne $wholefile) {
	    print "Write ".$self->temp_filename."\n" if $Debug;
	    my $fh = IO::File->new($self->temp_filename,"w") or die "%Error: $! writing ".$self->temp_filename."\n";
	    print $fh $wholefile;
	    $fh->close;
	}
    }

    # Find any files referenced.  Basically the line below
    #while ($wholefile =~ /^\#\s+\d+\s+\"([^\"]+)\".*$/mg) {
    # But doing a substr makes it .06sec/MB faster, which adds up for large compiles.
    my %checked_file;
    my $pos = -1;
    while (($pos = index($wholefile,"#",$pos+1)) >= 0) {
	if (substr($wholefile,$pos,150) =~ /^\#l?i?n?e?\s+\d+\s+\"([^\"]+)\"/) {
	    if (!$checked_file{$1}) {
		my $inc = $1;
		$checked_file{$inc} = 1;
		$self->included_file_check($inc);
	    }
	}
    }

    $md5->add($wholefile);

    return $md5->hexdigest;
}

sub included_file_check {
    my $self = shift;
    my $inc = shift;
    my $dir = $inc;
    #print "# FILE: $inc\n" if $Debug;
    if ($dir =~ s!^(.*/).*$!$1!) {
	foreach my $re (@{$self->{ok_include_regexps}}) {
	    return if ($dir =~ /$re/);
	}
	warn "objcache: %Warning: Strange include directory: $inc\n";
    }
}

sub preproc_cmds {
    my $self = shift;
    # Return commands for the preprocessor.  This should be overridden by superclasses.
    # For the base class, we'll simply concat the dep files.
    # (Just an example... If this was a real app, we'd hash the files directly instead.)
    return ("/bin/cat",$self->deps_lcl);
}

######################################################################
# Execution

sub execute {
    my $self = shift;
    # Execute the commands under a subshell

    $self->cc_running_lock() if !$self->icecream;

    my $host = $self->host;
    my @params = $self->compile_cmds;

    if ($host) {
	if ($self->distcc) {
	    $ENV{DISTCC_HOSTS}   ||= join(' ',@{$self->{remote_hosts}});
	    $ENV{DISTCC_SSH}     ||= ($ENV{OBJCACHE_RSH}||'rsh');
	    $ENV{DISTCC_VERBOSE} ||= 1 if $Debug;
	    unshift @params, ('distcc',);
	}
	elsif ($self->icecream) {
	    my $cc = shift @params;
	    $ENV{ICECC_DEBUG}    ||= 'debug' if $Debug;
	    $ENV{ICECC_CC}       ||= $cc;
	    $ENV{ICECC_CXX}      ||= $cc;
	    unshift @params, "/opt/icecream/bin/$cc";
	}
	else {
	    # -n gets around blocking waiting for stdin when 'make' is in the background
	    # FIX: Note this will break if we ever objcache some make target that requires stdin!
	    my $nice = (-f "/bin/nice") ? "/bin/nice" : "/usr/bin/nice";
	    unshift @params, (split(' ',$ENV{OBJCACHE_RSH}||'rsh'),
			      '-n', $host, 'cd', Cwd::getcwd(), '&&', $nice, '-9',);
	}
    }

    my $runtime = $self->run(@params);

    if ($self->tgts_missing) {
	my $waits = $self->{nfs_wait};
	while ($waits--) {
	    sleep (1); # Try a NFS propagation wait if it's not there yet.
	    last if !$self->tgts_missing;
	}
	if (my $tgt=$self->tgts_missing) {
	    die "objcache: %Error: $tgt not created (pwd=".Cwd::getcwd().", time=".time().")\n";
	}
    }

    $self->runtime($runtime);
}

sub compile_cmds {
    my $self = shift;
    # Return the commands needed to generate the targets.  This may be overriden by superclasses.
    return ($self->cmds_lcl);
}

######################################################################
# Execution

sub run {
    my $self = shift;
    my @params = @_;
    # Execute the commands.  Die on error.  Return runtime
    # Note don't print anything to stdout, or it will land in the output file!
    print STDERR "exec:\t",join(' ',@params),"\n" if $Debug;

    my $starttime = time();
    system @params;
    my $status = $?;

    $self->cc_running_unlock();
    if ($status != 0) {
	exit 10;
    }

    my $runtime = time() - $starttime;
    #print STDERR "  exec: time $runtime\n" if $Debug;
    return $runtime;
}

sub run_stdout {
    my $self = shift;
    my $to = shift;
    my @params = @_;
    # Redirect stdout to file
    open (SAVEOUT, ">&STDOUT") or croak "%Error: Can't dup stdout,";
    if (0) { print SAVEOUT "To prevent used only once"; }
    open (STDOUT, ">$to") or die "objcache %Error: $! writing $to\n";
    autoflush STDOUT 0;
    $self->run(@params);
    close(STDOUT);
    open (STDOUT, ">&SAVEOUT");
}

######################################################################
# Digest writing

sub encache {
    my $self = shift;
    # Take the compile results and put into the cache

    if ($Debug && $Debug>1) {
	foreach my $filename ($self->tgts_gbl) {
	    print "  Tgt: $filename\n";
	}
	foreach my $filename ($self->deps_gbl) {
	    print "  Dep: $filename\n";
	}
	use Data::Dumper; print Dumper($self);
    }

    my ($time,$fn) = Make::Cache::Hash::newest(filenames=>[$self->deps_lcl],);
    if (!$time) {
	warn "objcache: %Warning: Source file missing during compile: $fn\n";
	return;  # Don't cache it!!!
    }

    $self->runtime_write;

    if (($time||0) > (time()+2-($self->runtime))) {
	# If a src file changed within the time window we were compiling for... (w/2 sec slop)
	warn "objcache: -Info: Clock skew detected, or source file modified during compile: $fn\n";
	return;  # Don't cache it!!!
    }

    $self->SUPER::write();
}

######################################################################
# Runtime files

sub runtime {
    my $self = shift;
    my $setit = shift;
    # Read or set the runtime for the target list
    if (defined $setit) {
	$self->{runtime} = $setit;
	$self->{_runtime_cached} = 1;
    } elsif (!$self->{runtime} && !$self->{_runtime_cached}) {
	my $rt = Make::Cache::Runtime::read(key=>$self->runtime_key_digest);
	$self->{runtime} = $rt && $rt->{runtime};
	$self->{_runtime_cached} = 1;
    }
    return $self->{runtime};
}

sub runtime_write {
    my $self = shift;
    # Update the runtime database
    return if !$self->{runtime};
    Make::Cache::Runtime::write(key=>$self->runtime_key_digest,
			 persist=>{ key=>$self->runtime_key_digest,
				    #prog=>'objcache',  #smaller-> more likely to fit in directories
				    runtime=>$self->{runtime}, },
			 );
}

#######################################################################
# Compile running lock
# Simple "lock" -- not precise but fast.

sub cc_running_lock {
    my $self = shift;
    return if !$self->{remote_hosts}[0];
    return 1 if $self->distcc;  # Distcc will run jobs here too
    return 1 if $self->icecream;  # Icecream will run jobs here too
    return if $self->host;  # We're running remotely, ignore lockfile
    # Write a file to indicate there is a cc running now.
    $Cc_Running_Lock = 1;
    my $fh = IO::File->new(One_Compile_Filename,"w");
    #print "TOUCH ".One_Compile_Filename."\n";
    if (!$fh) {  # Non-fatal, as race case can do this, & it's no reason to abort the compilation
	warn "objcache: -Note: $! writing ".One_Compile_Filename."\n";
	return;
    }
    $fh->close();
}

sub cc_running_unlock {
    my $self = shift;
    return if !$self->{remote_hosts}[0];
    return if !$Cc_Running_Lock;
    print "RM ".One_Compile_Filename."\n" if $Debug;
    $Cc_Running_Lock = 0;
    unlink(One_Compile_Filename);  # Ok if fails
}

sub is_cc_running_read {
    my $self = shift;
    return undef if !$self->{remote_hosts}[0];
    return 1 if $self->distcc;  # Distcc will run jobs here too, so no one-running test or will overload local machine
    return 1 if $self->icecream;  # Icecream will run jobs here too, so no one-running test or will overload local machine
    # Return true if CC is running now
    my @stat = stat(One_Compile_Filename);
    my $mtime = $stat[9];
    return (!$mtime || $mtime < (time() - One_Delay_Override));
}

sub host {
    my $self = shift;
    if (!defined $self->{host}) {
	# Pick a host to use
	return "icecream" if $self->icecream; # Doesn't need remote_hosts
	return undef if !$self->{remote_hosts}[0];
	return "distcc" if $self->distcc; # Needs remote_hosts
	return undef if $self->runtime && $self->{min_remote_runtime} && ($self->runtime < $self->{min_remote_runtime});
	my $rnd = int(rand($#{$self->{remote_hosts}}+1));
	$self->{host} = $self->{remote_hosts}[$rnd];
	$self->{host} = 0 if $self->{host} eq $Hostname || $self->{host} eq 'localhost';	# No need to remote it
    }
    return $self->{host};
}

######################################################################
1;
__END__

=pod

=head1 NAME

Make::Cache::Obj - Caching of object and test run information

=head1 SYNOPSIS

my $oc = Make::Cache::Obj->new (...);
$oc->parse_cmds;
$oc->tgts_unlink;
$oc->preproc;
my $ochit = $oc->find_hit;
if ($ochit) {
    $ochit->restore;
} else {
    # Run command passed
    $oc->execute;
    $oc->encache;
}

=head1 DESCRIPTION

Make::Cache::Obj is a superclass of Make::Cache.  It provides support for
executing a list of commands if the cache misses, and for determining the
runtime of the commands that will execute.

Objects that represent specific compilers use this as a base class.

=head1 FUNCTIONS

=over 4

=item cc_running_lock ()

Set a non-reliable semaphore to indicate a compile is running.

=item cc_running_unlock ()

Clear a non-reliable semaphore to indicate a compile is running.

=item is_cc_running_read ()

Return true if a compile is running on any machine.

=item compile_cmds

Return list of commands to run in the execute() phase.

=item encache

Take the compile results and put them into the cache.

=item execute

Run the compiler, perhaps on a remote machine.

=item ok_include_regexps

Set the list of regexp references that are acceptable global includes.

=item host

Return the name of a remote host to run the compilation on, or 0 for the
local host.  If the compile time is less then the min_remote_runtime
variable, the compile will always be done locally.  Else, the host is
chosen randomly from elements in the remote_hosts list.

=item included_file_check

Prevent users from including global files that are not the same on all
machines, by warning about any includes with directories specified.
Directories that are OK should be included in the list returned by
ok_include_regexps.

=item parse_cmds

Parses the local commands to extract target filenames and compiler switches.

=item preproc

Executes a compiler run to create a temporary file containing all source to
be hashed.

=item preproc_cmds

Return list of commands to run in the preproc() phase.

=item temp_filename

Return the name of a temporary file.  With argument, set the name of a
temporary file to be deleted in a END block or on errors.

=item run (params...)

Execute a system command with the specified commands, timing how long it
takes and detecting errors.

=item run_stdout (filename, params...)

Run() with redirection of stdout to the first argument.

=item runtime

Return a runtime object for the given targets.

=item runtime_write

Write the runtime object to persistent storage.  Called on completion of a
compile.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.com/>.

Copyright 2000-2005 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<objcache>, L<Make::Cache>, L<Make::Cache::Runtime>, L<Make::Cache::Gcc>

=cut

######################################################################
