#!/usr/local/bin/perl -w
#$Revision: #7 $$Date: 2004/02/12 $$Author: wsnyder $
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

require 5.006_001;
package Make::Cache::Runtime;
use DirHandle;
use Digest::MD5;
use File::Copy;
use File::Path;
use Storable;
use Carp;

use strict;

our $VERSION = '1.012';

#######################################################################

our $Cache_Dir = undef;   # Set/accessed with cache_dir function

#######################################################################

sub cache_dir {
    $Cache_Dir ||= $ENV{OBJCACHE_RUNTIME_DIR} || "/usr/local/common/lib/runtime";
    $Cache_Dir = shift if $_[0];
    return $Cache_Dir;
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
    mkpath ($path, 0, 0777);
    my $filename = "$path/${key_digest}.runtime";
    print "Make::Cache::Runtime::write $filename\n" if $::Debug;
    Storable::nstore ($params{persist}, "${filename}.new");
    chmod 0777, "${filename}.new";
    # Do the copy as one atomic op to prevent a race case with another reader
    move ("${filename}.new", "$filename");
}

sub read {
    my %params = (dir => cache_dir(),	# Directory to put results into
		  #key => ,		# Key to be stored
		  @_);
    # Returns reference to persistent structure, undef if no data known

    my $key_digest = Digest::MD5::md5_hex($params{key});
    (my $key_prefix = $key_digest) =~ s/^(..).*$/$1/;
    my $filename = "$params{dir}/${key_prefix}/${key_digest}.runtime";
    return undef if ! -r $filename;
    my $persistref = Storable::retrieve($filename);
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
directory.

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

=head1 SEE ALSO

C<Make::Cache>

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################
