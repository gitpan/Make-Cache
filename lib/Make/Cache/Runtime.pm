# See copyright, etc in below POD section.
######################################################################

require 5.006_001;
package Make::Cache::Runtime;
use DirHandle;
use Digest::MD5;
use File::Copy;
use File::Path;
use Storable;
use Carp;

use strict;

our $VERSION = '1.052';

#######################################################################

our $_Cache_Dir = undef;   # Set/accessed with cache_dir function

#######################################################################

sub cache_dir {
    $_Cache_Dir ||= $ENV{OBJCACHE_RUNTIME_DIR} || "/usr/local/common/lib/runtime";
    $_Cache_Dir = shift if $_[0];
    return $_Cache_Dir;
}

sub format_time {
    my $secs = shift;
    my $include_hours = shift;
    # Hopefully, no hours!
    if ($include_hours || $secs>=3600) {
	return sprintf ("%02d:%02d:%02d", int($secs/3600), int(($secs%3600)/60), $secs % 60);
    } else {
	return sprintf ("%02d:%02d", int(($secs)/60), $secs % 60);
    }
}

sub write {
    my %params = (dir => cache_dir(),	# Directory to put results into
		  #key => ,		# Key to be stored
		  #persist => {},	# Reference to hash to be stored
		  @_);
    $params{key} or die "%Error: Expecting key=> parameter, ";
    $params{persist} or die "%Error: Expecting key=> parameter, ";

    # We store it under a digest to allow for non-filename allowed characters
    my $key_digest = Digest::MD5::md5_hex($params{key});
    (my $key_prefix = $key_digest) =~ s/^(..).*$/$1/;
    my $path = "$params{dir}/${key_prefix}";
    my $filename = "$path/${key_digest}.runtime";
    print "Make::Cache::Runtime::write $filename\n" if $::Debug;
    my $newfile = "${filename}.new$$";
    # Ignore errors, as two processes may be doing this at once
    # If the output dir isn't made the storable creation will catch it
    # And if it fails, we'll live.
    my $check = eval {
	my_mkpath ($path);
	Storable::nstore ($params{persist}, $newfile);
	chmod 0777, $newfile;
	# Do the copy as one atomic op to prevent a race case with another reader
	move ($newfile, "$filename");
	'ok';
    };
    if ($check ne 'ok') {
	warn "-Info: Runtime stashing failed:".($@||"")."\n";
    }
}

sub read {
    my %params = (dir => cache_dir(),	# Directory to put results into
		  #key => ,		# Key to be stored
		  @_);
    # Returns reference to persistent structure, undef if no data known

    my $key_digest = Digest::MD5::md5_hex($params{key});
    (my $key_prefix = $key_digest) =~ s/^(..).*$/$1/;
    my $filename = "$params{dir}/${key_prefix}/${key_digest}.runtime";

    # We can't have storable open the file for us, as there may be a race
    # where the file exists with -r, then gets replaced.
    my $fd = IO::File->new("<$filename");
    return undef if !$fd;
    my $persistref;
    eval { $persistref = Storable::fd_retrieve($fd); };  # Ignore errors
    return $persistref;
}

sub dump {
    my %params = (dir => cache_dir(),	# Directory to put results into
		  @_);

    my $path = $params{dir};
    my $dir = new DirHandle $path or return;
    my %lines;
    while (defined(my $basefile = $dir->read)) {
	my $file = "$path/$basefile";
	if ($file =~ /\.runtime$/) {
	    my $persistref = Storable::retrieve($file);
	    my $date = (stat($file))[9];
	    my ($a,$b,$c,$day,$month,$year,$d,$e,$f) = localtime($date);
	    $date = sprintf("%04d/%02d/%02d", $year+1900,$month+1,$day);
	    (my $showfile = $basefile) =~ s/\.runtime//;
	    $lines{$persistref->{prog}.$persistref->{key}}
	    = sprintf ("\t%-9s %-8s %-11s %s %s\n",
		       $persistref->{prog}||'?',
		       format_time($persistref->{runtime},1),
		       $date,
		       $showfile,
		       $persistref->{key});
	}
    }
    foreach (sort(keys %lines)) { print $lines{$_}; }
}

sub my_mkpath {
    my($paths, $verbose, $mode) = @_;
    # $paths   -- either a path string or ref to list of paths
    # $verbose -- optional print "mkdir $path" for each directory created
    # $mode    -- optional permissions, defaults to 0777
    #
    # Like File::Path::mkpath, where this is from.
    # But that insists on printing messages and failing when it doesn't
    # work, which can happen when many processes are executing in parallel
    local($")="/";
    $mode = 0777 unless defined($mode);
    $paths = [$paths] unless ref $paths;
    my (@created,$path);
    foreach $path (@$paths) {
	$path .= '/' if $^O eq 'os2' and $path =~ /^\w:\z/s; # feature of CRT
	next if -d $path;
	my $parent = File::Basename::dirname($path);
	unless (-d $parent or $path eq $parent) {
	    push(@created,my_mkpath($parent, $verbose, $mode));
	}
	print "mkdir $path\n" if $verbose;
	unless (mkdir($path,$mode)) {
	    my $e = $!;
	    # allow for another process to have created it meanwhile
	    #croak "mkdir $path: $e" unless -d $path;
	}
	push(@created, $path);
    }
    @created;
}

#######################################################################
1;
__END__

=pod

=head1 NAME

Make::Cache::Runtime - Simple database of completion times

=head1 SYNOPSIS

   $string = format_time($seconds, $true_to_including_hours);
   Make::Cache::Runtime::write (key=>$key,
			 persist=>{testing_persistence=>1},
			 );
   my $persistref = Make::Cache::Runtime::read (key=>'make::runtime testing',);

=head1 DESCRIPTION

Make::Cache::Runtime allows for storing and retrieving persistent state,
namely expected runtime of gcc and tests.

Data is stored in a global directory, presumably under NFS mount across all
systems.  While this does not allow atomic access to files, it does provide
fast, catchable access to the database.

=head1 METHODS

=over 4

=item cache_dir

Return the default directory name for the cache.  With optional argument,
set the cache directory name.  Defaults to OBJCACHE_RUNTIME_DIR.

=item $string = format_time($seconds, $true_to_including_hours);

Return the time in seconds as a string in MM:SS format.  With true second
argument, return as HH:MM:SS.

=item write (key=>$key, persist=>$ref);

Hash the key, and write a database entry file with a copy of the data in
the persist reference.  With dir=> named parameter, use database in that
directory.  Note to prevent problems between different versions of perl, you
may want to include the Perl version number in the key hash.

=item my $ref = read (key=>$key);

Return a object reference for the data stored under the given key, or undef
if not found.  With dir=> named parameter, use database in that directory.

=item dump()

Print a summary of the runtime database for debugging.  With dir=> named
parameter, use database in that directory.

=back

=head1 FILES

/usr/local/common/lib/runtime		Default for cache_dir()

=head1 ENVIRONMENT

=over 4

=item OBJCACHE_RUNTIME_DIR

Specifies the directory containing the runtime database.  Defaults to
/usr/local/common/lib/runtime.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2000-2010 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License Version 3 or the Perl Artistic License
Version 2.0.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<objcache>, L<Make::Cache>

=cut

######################################################################
