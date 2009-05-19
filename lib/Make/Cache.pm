# See copyright, etc in below POD section.
######################################################################

package Make::Cache;
use IO::File;
use IO::Pipe;
use IO::Dir;
use Data::Dumper;
use File::Copy;
use File::Path;
use Storable;
use Digest::MD5;
use Sys::Hostname;
use Cwd;
use Data::Dumper; $Data::Dumper::Indent=1;

use Make::Cache::Hash;
use Make::Cache::Runtime;
use Carp;
use strict;

our $Debug;

our $VERSION = '1.051';

######################################################################
#### Creators

sub new {
    my $class = shift;
    my @inherit = %{$class} if ref $class;
    my $self = {
	# Global Defaults
	#dir => "path_to_cache_dir",
	read=>1,	# Allow cache to have read hits
	write=>1,	# Allow cache to write updated status
	clean_delay=>(24*60*60),	# After this many seconds, clean may delete the file
	pwd=>Cwd::getcwd(),
	file_env => [ 	# List of global mnemonic and local value for global_filename funcs (not hash-can be duplicates)
			PWD => Cwd::getcwd(),
			],
	# Per-file elements
	tgts_lcl => [],
	deps_lcl => [],
	cmds_lcl => [],
	flags_lcl => [],
	@inherit,
	@_,
    };
    $self->{dir} or croak "%Error: Need to specify repository dir,";
    ($self->{dir}=~/^\//) or croak "%Error: Repository dir must be absolute path,";
    bless $self, ref($class)||$class;
}

sub clear_hash_cache {
    Make::Cache::Hash::clear_cache();
}

#######################################################################
# Accessors

sub cmds_lcl {
    my $self = shift;
    # List of commands to be executed
    push @{$self->{cmds_lcl}}, @_ if defined $_[0];
    return @{$self->{cmds_lcl}};
}
sub flags_lcl {
    my $self = shift;
    # List of commands to be hashed, thus is generally cmds_lcl minus -D/-U/-I switches
    push @{$self->{flags_lcl}}, @_ if defined $_[0];
    return @{$self->{flags_lcl}};
}
sub deps_lcl {
    my $self = shift;
    # List of filename dependencies used to create the targets
    push @{$self->{deps_lcl}}, @_ if defined $_[0];
    return @{$self->{deps_lcl}};
}
sub tgts_lcl {
    my $self = shift;
    # List of filename targets to be cached
    push @{$self->{tgts_lcl}}, @_ if defined $_[0];
    return @{$self->{tgts_lcl}};
}

sub cmds_gbl {
    my $self = shift;
    return map {$self->global_filename($_);} $self->cmds_lcl;
}
sub deps_gbl {
    my $self = shift;
    return nodup(map {$self->global_filename($_);} $self->deps_lcl);
}
sub flags_gbl {
    my $self = shift;
    return nodup(map {$self->global_filename($_);} $self->flags_lcl);
}
sub tgts_gbl {
    my $self = shift;
    return nodup(map {$self->global_filename($_);} $self->tgts_lcl);
}

sub tgts_name_digest {
    my $self = shift;
    # Internal; create digest based on target names
    $self->{tgts_name_digest} ||= Make::Cache::Hash::hash (text=>[ $self->tgts_gbl ]);
    return $self->{tgts_name_digest};
}

sub runtime_key_digest {
    my $self = shift;
    # Internal; create digest based on target names and executable
    $self->{runtime_key_digest} ||= Make::Cache::Hash::hash (text=>[ $self->tgts_gbl, $self->{cmds_exec} ]);
    return $self->{runtime_key_digest};
}

sub deps_data_digest {
    my $self = shift;
    my $hash = $self->deps_fixed_digest;
    # Internal; create digest based on target contents
    if (!$hash) {
	my @dep_to_do = nodup($self->deps_lcl);
	@dep_to_do = sort(@dep_to_do);
	$hash = Make::Cache::Hash::hash (filenames=>[ @dep_to_do ],
				  text=>[ $self->flags_gbl ],);
	#print "\tHash $hash\n\tof ",(join ' ',@dep_to_do),"\n\tCmd=",(join ' ',$self->flags_gbl), "\n" if $Debug;
    }
    return $hash;
}

sub deps_fixed_digest {
    # If defined, this returns a digest which is known to contain all relevant
    # source hash information, and thus avoids having to do read dependencies
    # as each cache entry is compared.
    return undef;
}

sub nodup {
    my @o;
    my %o;
    foreach (@_) {
	next if $o{$_};
	$o{$_} = 1;
	push @o, $_;
    }
    return @o;
}

#######################################################################
# Methods, may be overloaded

sub global_filename {
    my $self = shift;
    my $filename = shift;
    for (my $i=0; $i<=$#{$self->{file_env}}; $i+=2) {
	my ($key, $val) = ($self->{file_env}[$i], $self->{file_env}[$i+1]);
	$filename =~ s/^$val/\$\$${key}\$\$/;
    }
    return $filename;
}

sub local_filename {
    my $self = shift;
    my $filename = shift;
    for (my $i=0; $i<=$#{$self->{file_env}}; $i+=2) {
	my ($key, $val) = ($self->{file_env}[$i], $self->{file_env}[$i+1]);
	$filename =~ s/^\$\$${key}\$\$/$val/;
    }
    return $filename;
}

#######################################################################
# Digest writing

sub write {
    my $self = shift;

    # We don't clear the cache, this means we almost certainly have the hashes of
    # the source code when we started the process.  This is safer, as it allows for
    # the user to change the code while running a build, and not caching the wrong
    # results.

    # What should we put into the file?
    my $store = {
	deps_gbl => [$self->deps_gbl],	# Dependencies expressed in local filesystem filenames
	flags_gbl => [$self->flags_gbl],# Command to be hashed (cmds_gbl minus flags that don't matter)
	tgts_gbl => [$self->tgts_gbl],	# Targets expressed in local filesystem filenames
	deps_data_digest => $self->deps_data_digest,
	tgts_name_digest => $self->tgts_name_digest,
	time => time(),
	pwd  => $self->{pwd},
    };

    #print Dumper($store) if $Debug;

    # Write it out
    if (!-w $self->{dir}) {
	mkpath $self->{dir}, 0777;
	if (!-w $self->{dir}) {
	    warn ("%Warning: Cache.pm: Cannot write dir '$self->{dir}' to cache '$store->{tgts_gbl}[0]'.\n");
	    return;
	}
    }

    if (my $tgt = $self->tgts_missing) {
	warn "%Warning: Cache.pm: Expected target file wasn't generated: $tgt\n";
	return;
    }

    (my $digPrefix = $store->{tgts_name_digest}) =~ s/^(..).*$/$1/;
    my $pathtgt = "$self->{dir}/$digPrefix/$store->{tgts_name_digest}";
    mkpath ($pathtgt, 0, 0777);
    my $pathfile = "$pathtgt/$store->{deps_data_digest}";
    Storable::nstore ($store, "$pathfile.digest.new$$");
    chmod (0666, "$pathfile.digest.new$$");
    for (my $n=0; $n<=$#{$store->{tgts_gbl}}; $n++) {
	my $tgt = $self->{tgts_lcl}[$n];
	my $to = "$pathfile.t${n}.new$$";
	print "    cp $tgt $to\n" if $Debug;
	copy ($tgt, "$pathfile.t${n}.new$$");
    }
    # Do the copy as one atomic op to reduce race case with another reader
    for (my $n=0; $n<=$#{$store->{tgts_gbl}}; $n++) {
	move ("$pathfile.t${n}.new$$", "$pathfile.t${n}");
    }
    move ("$pathfile.digest.new$$", "$pathfile.digest");
}

########################################################################
## Digest reading

use vars qw($_Test_Remove_Target); # Testing only!

sub restore {
    my $self = shift or return;
    # Call this with the results of a find_hit
    # Restores the cached files.
    # Returns self if ok, else undef

    my $pathfile = $self->{hit_filename} or die "%Error: Not called on a hit object,";

    # Update the digest date, so cleaning won't consider it unsed
    touch("${pathfile}.digest");

    my $failed;
    for (my $n=0; $n<=$#{$self->{tgts_lcl}}; $n++) {
	my $tgt = $self->{tgts_lcl}[$n];
	my $from = "$pathfile.t${n}";
	unlink $tgt;
	if (!-r $from) {
	    warn "objcache: -Info: Ignoring Cache: Cache files missing for $from\n";
	    $failed=1; last;
	}
	# Can't hard link, as might be on different file system
	unlink($from) if $_Test_Remove_Target;

	if ($self->{link}) {
	    print "    ln -s $from $tgt\n" if $Debug;
	    if (!symlink $from, $tgt) {
		warn "objcache: -Info: Ignoring cache: Can't ln -s $from $tgt: $!\n";
		$failed=1; last;
	    }
	} else {
	    print "    cp $from $tgt\n" if $Debug;
	    if (!copy $from, $tgt) {
		warn "objcache: -Info: Ignoring cache: Can't cp $from $tgt: $!\n";
		$failed=1; last;
	    }
	}
	touch($tgt);
    }

    if ($failed) {
	# Recover nicely by blowing away the cache entry
	unlink ("$pathfile.digest");
	for (my $n=0; $n<=$#{$self->{tgts_lcl}}; $n++) {
	    my $from = "$pathfile.t${n}";
	    unlink $from;
	}
	return undef;
    }

    return $self;
}

sub find_hit {
    my $self = shift;
    # Return new Make::Cache reference to the cache hit on ANY ENTRY for this file
    # Or undef if we're unlucky

    (my $digPrefix = $self->tgts_name_digest) =~ s/^(..).*$/$1/;
    my $pathtgt = "$self->{dir}/$digPrefix/".$self->tgts_name_digest;

    my $dfixed = $self->deps_fixed_digest;
    if ($dfixed) {
	my $file = "$pathtgt/$dfixed";
	print "Digests_read_fixed $file\n" if $Debug;
	if (-r "$file.digest") {
	    return $self->_find_hit_ent ($file);
	}
    }
    else {
	print "Digests_read_dir $pathtgt\n" if $Debug;
	my $dir = new IO::Dir $pathtgt or return undef;
	while (defined(my $basefile = $dir->read)) {
	    my $file = "$pathtgt/$basefile";
	    if ($file =~ s/\.digest$//) {
		if (my $hitref = $self->_find_hit_ent ($file)) {
		    return $hitref;
		}
	    }
	}
    }
    return undef;
}

sub _find_hit_ent {
    my $self = shift;
    my $pathfile = shift;
    # Return new object if there is a cache hit for THIS ENTRY

    print "     Try $pathfile\n" if $Debug;
    my $digestref = Storable::retrieve("${pathfile}.digest");

    my @dl = map {$self->local_filename($_);} @{$digestref->{deps_gbl}};
    my @tl = map {$self->local_filename($_);} @{$digestref->{tgts_gbl}};

    my $hitref = $self->new(deps_lcl => [@dl],
			    tgts_lcl => [@tl],
			    #flags_lcl => [],	# Same as what we searched for
			    hit_filename => $pathfile,
			    );
    #print Dumper($hitref) if $Debug;

    my $hithash = $hitref->deps_data_digest;
    if (!$hithash) {
	print "\tMiss, dep doesn't exist\n" if $Debug;
	return undef;
    }
    if ($hithash ne $digestref->{deps_data_digest}) {
	print "\tMiss, digest mismatch ",$hithash," incache ",$digestref->{deps_data_digest},"\n" if $Debug;
	return undef;
    }
    print "\tDepend MATCH ${pathfile}\n" if $Debug;
    return $hitref;
}

#######################################################################
# Utilities

sub tgts_missing {
    my $self = shift || die;
    # Return filename if all target files don't exist
    foreach my $tgt ($self->tgts_lcl) {
	return $tgt if (!-r $tgt);
    }
    return undef;
}

sub tgts_unlink {
    my $self = shift || die;
    # Unlink any targets that exist
    foreach my $tgt ($self->tgts_lcl) {
	unlink $tgt;
    }
}

sub touch {
    my $file = shift;
    # There is a bug in redhat 7.2 where utime doesn't work
    #my $now = time; utime $now, $now, $file or carp "%Warn: Can't touch $file,";
    my $buf;
    my $fh = IO::File->new($file,"r+");
    $fh->sysread($buf,1);
    $fh->sysseek(0,0);
    $fh->syswrite($buf,1);
    $fh->close();
}

#######################################################################
# Cleaning

sub clean {
    my $self = shift || die;
    # Clean all old files in the repository
    my $purgetime = time() - $self->{clean_delay};
    $self->_clean_dir($purgetime, $self->{dir});
}

sub _clean_dir {
    my $self = shift;
    my $purgetime = shift;
    my $path = shift;
    # Clean one dir, return true if files exist
    my $dir = new IO::Dir $path or return;
    my $keepdir = 0;
    while (defined(my $basefile = $dir->read)) {
	my $file = "$path/$basefile";
	next if ($basefile eq "." || $basefile eq "..");
	if (-d $file) {
	    if (_clean_dir ($self, $purgetime, $file)) {
		$keepdir = 1;
	    } else {
		print "  Removing old dir $file\n" if $Debug;
		eval { rmtree $file,0,1; }   # Quietly...
	    }
	} elsif ($file =~ /\.digest$/) {
	    # We look at modtime, as it's faster and prevents death if it's malformed
	    my $mtime = (stat($file))[9];
	    if ($mtime && $mtime > $purgetime) {
		$keepdir = 1;
	    } else {
		print "  Removing old file $file\n" if $Debug;
		unlink $file;
		for (my $i=0; $i<10; $i++) {
		    (my $tfile = $file) =~ s/\.digest$/.t${i}/;
		    print "  Removing old file $tfile\n" if $Debug;
		    unlink $tfile;
		}
	    }
	}
    }
    #print "Depend_clean_dir $keepdir $path\n" if $Debug;
    return $keepdir;
}

#######################################################################
# Dump

sub dump {
    my $self = shift;

    my $infor = {
	dumpone => 1,
	rm => 0,	# If set, show the command to clean it up
	@_,
    };

    _dump_recurse($self,$infor, $self->{dir});

    printf +("\t%-11s %-11s %3s %3s %-32s %-5s %-20s %s\n",
	     "CREATED",
	     "LAST_HIT",
	     "Tgt",
	     "Dep",
	     "Hash",
	     "Cmd",
	     "Tgt[0]",
	     ($infor->{rm}?"RM":"Pwd"),
	     );
    foreach (sort(keys %{$infor->{lines}})) { print $infor->{lines}{$_}; }
}

sub _dump_recurse {
    my $self = shift;
    my $infor = shift;
    my $path = shift;

    my $dir = new IO::Dir $path or return;
    my $n=0;
    while (defined(my $basefile = $dir->read)) {
	my $file = "$path/$basefile";
	if ($basefile ne "." && $basefile ne ".." && -d $file) {
	    _dump_recurse($self,$infor,$file);
	}
	elsif ($file =~ /\.digest$/) {
	    my $persistref = Storable::retrieve($file);
	    print "$file\n" if $Debug;
	    if ($infor->{dumpone}) {
		#print Dumper($persistref);
		$infor->{dumpone} = 0;
	    }
	    my $cdate; my $mdate;
	    {my $date = (stat($file))[9];
	     my ($a,$b,$c,$day,$month,$year,$d,$e,$f) = localtime($date);
	     $mdate = sprintf("%04d/%02d/%02d", $year+1900,$month+1,$day);}
	    {my ($a,$b,$c,$day,$month,$year,$d,$e,$f) = localtime($persistref->{time});
	     $cdate = sprintf("%04d/%02d/%02d", $year+1900,$month+1,$day);}

	    (my $showfile = $basefile) =~ s/\.digest//;
	    (my $key = $persistref->{tgts_gbl}[0]) =~ s/.*\///;
	    (my $cc  = $persistref->{flags_gbl}[0]) =~ s/.*\///;

	    # Convert old cache repository to new form
	    $persistref->{tgts_gbl} ||= [$persistref->{tgtfile}];
	    $persistref->{deps_gbl} ||= $persistref->{depends};

	    (my $rm = "/bin/rm $file") =~ s/\.digest$/*/;

	    $infor->{lines}{$key."_".$mdate.$n++}
	    = sprintf ("\t%-11s %-11s %3d %3d %-32s %-5s %-20s %s\n",
		       $cdate,
		       $mdate,
		       $#{$persistref->{tgts_gbl}}+1,
		       $#{$persistref->{deps_gbl}}+1,
		       $showfile,
		       $cc,
		       $key,
		       ($infor->{rm} ? $rm : $persistref->{pwd}),
		       );
	}
    }
}

#######################################################################
1;
__END__

=pod

=head1 NAME

Make::Cache - Caching of object and test run information

=head1 SYNOPSIS

  my $oc = Make::Cache->new (...)
  $oc->write
  if (my $hit = $oc->find_hit) {
    $hit->restore;
  }
  $oc->dump

=head1 DESCRIPTION

Make::Cache is used to accelerate the generation of makefile targets.
When a target is to be created, it is looked up in the cache.  On a miss,
the hash of the source files, and all the generated targets are stored.

Next time the target is needed, the cache will hit, and the target files
may be retrieved from the cache instead of being regenerated.

The Make::Cache class is generally used as a base class for more specific
classes.

=head1 LOCAL TO GLOBAL

Make::Cache converts local filenames to global filenames.  This gets around
the problem of compile lines similar to

    gcc /user/a/home_dir/foo.c

resulting in cache misses, because someone else compiled the exact same source
in a different directory

    gcc /user/b/home_dir/foo.c

To avoid this, all filenames are converted to global format, by using a
file_env list passed in the new constructor.  By default, this converts the
current working directory (cwd) to $CWD.  Using the examples above, the gcc
command line would be hashed as if the user typed:

    gcc $$CWD$$/foo.c

Which is identical for both users, and thus will result in cache hits.

=head1 FUNCTIONS

=over 4

=item new

Create a new Cache::Hash object.  Named parameters may be specified:

=over 4

=item clean_delay

Number of seconds a object must be in age before clean() may delete it.
Default is one day (24*60*60).

=item file_env

List of environment variables for substitution, see LOCAL TO GLOBAL
section.

=item read

Defaults true to enable finding hits in the cache.

=item write

Defaults true to enable writing updates to the cache.

=back

=item clear_hash_cache

If a source file changes, this function must be called to clear out a
temporary internal cache.

=item clean

Clean the cache.  See the clean_delay variable.

=item cmds_gbl

Return list of commands, relative to all users.  This is used in hashing;
see LOCAL TO GLOBAL section.

=item cmds_lcl

Return list of commands, relative to the local user, that should be
executed.  With parameter, add the specified command.

=item deps_gbl

Return list of source dependency filenames, relative to all users.  This is
used in hashing; see LOCAL TO GLOBAL section.

=item deps_lcl

Return list of source dependency filenames, relative to the local user,
that should be executed.  With parameter, add the specified filename.

=item

For debugging, dump the current contents of the compile cache.

=item flags_gbl

Return list of compile flags, relative to all users.  This is used in
hashing; see LOCAL TO GLOBAL section.

=item flags_lcl

Return list of compile flags, relative to the local user, that should be
executed.  With parameter, add the specified flag.

=item global_filename

Given a local filename, return the filename in global format.  See LOCAL TO
GLOBAL section.

=item local_filename

Given a global filename, return the filename in local format.  See LOCAL TO
GLOBAL section.

=item nodup

Given a input list, return the list with any duplicates removed.

=item tgts_gbl

Return list of target filenames, relative to all users.  This is used in
hashing; see LOCAL TO GLOBAL section.

=item tgts_lcl

Return list of target filenames, relative to the local user, that should be
executed.  With parameter, add the specified filename.

=item tgts_missing

Return the filename of any local targets that are not currently on disk.
Return undef if all targets exist.

=item tgts_unlink

Remove all local target files.

=item write

Write the cache digest.

=item restore (object_from_find_hit)

Given a object returned from find_hit, restore any target files to the
local compile area.  Return $self if successful, else undef.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2000-2009 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License Version 3 or the Perl Artistic License
Version 2.0.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<objcache>, L<Make::Cache::Runtime>, L<Make::Cache::Hash>,
L<Make::Cache::Obj>, L<Make::Cache::Gcc>

=cut

######################################################################
