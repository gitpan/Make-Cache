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

package Make::Cache::Hash;
use IO::File;
use Digest::MD5;
use Carp;

use strict;
use vars qw ($Debug);

our $VERSION = '1.011';

#######################################################################

#######################################################################
# Dependency reading

sub dfile_read {
    my %params = (#filename=>"",	# File to be read
		  @_);
    # Read a dependency (.d) file into %Deps hash
    # Return hash reference of {targets}{depends} = 1
    # Mostly from SystemC::sp_makecheck

    $params{filename} or carp "Must specify filename=>,";
    my $fh = IO::File->new($params{filename}) or die "$0: %Error: $! depending $params{filename}\n";
    my $line = "";
    
    my %all_deps;
    while (defined (my $thisline = $fh->getline())) {
	chomp $thisline;
	$line .= $thisline;
	next if ($line =~ s/\\s*$/ /);
	next if ($line =~ /^\s*$/);
	if ($line =~ /^([^:]+):([^:]*)$/) {
	    my $tgtl = $1;  my $depl = $2;
	    my @tgts = ($params{filename});	# Imply the .d is a target
	    foreach my $tgt (split /\s+/,"$tgtl ") {
		next if $tgt eq "";
		push @tgts, $tgt;
	    }
	    foreach my $dep (split /\s+/,"$depl ") {
		next if $dep eq "";
		foreach my $tgt (@tgts) {
		    $all_deps{$tgt}{$dep} = 1;
		}
	    }
	} else {
	    die "$0: %Error: $params{filename}:$.: Strange dependency line: $line\n";
	}
	$line = "";
    }
    $fh->close;
    return (\%all_deps);
}

#######################################################################
# Hashing

sub hash {
    my %params = (filenames => [],	# Array ref of files to be hashed
		  text => [],		# Array ref of constant text to be hashed
		  defines => {},	# Hash ref of defines to search for and mark defined
		  ignore_rcs => 1,	# Ignore $ Id  comments in the text
		  @_);
    # Hash the given text and files, return the hash
    # If file doesn't exist or other error, warn and return undef.

    my $md5 = Digest::MD5->new;
    # We sort and eliminate duplicate filenames, so ordering won't result in differing hashes
    my %didfn;
    foreach my $depfile (sort @{$params{filenames}}) {
	next if $didfn{$depfile};
	$didfn{$depfile} = 1;

	my $filedigest = _hash_a_file(\%params, $depfile);
	return undef if !$filedigest;
	$md5->add($filedigest);
	$params{subhashes}{$depfile} = $filedigest if $Debug;
    }

    # We DON'T sort the text, order presumed to matter
    foreach my $text (@{$params{text}}) {
	$md5->add($text);
	$params{subhashes}{$text} = 'added' if $Debug;
    }

    my $digest = $md5->hexdigest;
    if ($Debug) {
	print "MD $md5\n";
	use Data::Dumper;
	print "Make::Cache::Hash $digest <--\n";
	print Dumper(\%params),"\n";
    }
    # Mystery: Passing a $md5 object to the caller resets the hash!
    return $digest;
}

use vars qw (%Hash_Cache);
sub clear_cache {
    %Hash_Cache = ();
}
sub _hash_a_file {
    my $self = shift;
    my $filename = shift;
    if ($Hash_Cache{$filename}) {
	print "HASHIT_Hit $filename\n" if $Debug;
	my $cache_ent = $Hash_Cache{$filename};
	foreach my $def (keys %{$self->{defines}}) {
	    (defined $cache_ent->{defines}{$def})
		or die "%Error: Badly cached $filename for define $def,";
	    if ($cache_ent->{defines}{$def}) {
		$self->{defines}{$def} = 1;  # We never reset it; any usage in any file is a "usage"
	    }
	}
	return $cache_ent->{digest};
    }
    print "HASHIT_New       $filename\n" if $Debug;

    my $md5 = Digest::MD5->new;
    my $fh = IO::File->new($filename);
    if (!$fh) {
	warn "$0: -Info: $! hashing $filename\n" if $Debug;
	return undef;
    }

    # Read the file.  Flwoop in one big chunk.
    local $/; undef $/;
    my $wholefile = <$fh>;
    #print "HASH_A_FILE $filename  >>>>>>>>\n$wholefile<<<<<<<\n";
    if ($self->{ignore_rcs}) {
	$wholefile =~ s/(\$ (I d | R evision | D ate | A uthor | H eader ) :)[^\n\"\$]+\$/$1/gx;
    }
    $md5->add($wholefile);
    $fh->close();

    my $cache_ent = {};
    foreach my $def (keys %{$self->{defines}}) {
	if ($wholefile =~ m/$def/m) {
	    $self->{defines}{$def} = 1;
	    $cache_ent->{defines}{$def} = 1;
	    #print "FOUNDDEF!!!!! $filename !!! '$def'\n" if $Debug
	} else {
	    $cache_ent->{defines}{$def} = 0;
	    #print "NoDEF         $filename !!! '$def'\n" if $Debug
	}
    }

    $cache_ent->{digest} = $md5->hexdigest;
    $Hash_Cache{$filename} = $cache_ent;
    print "\tDIGEST $filename\t$cache_ent->{digest}\n" if $Debug;
    return $cache_ent->{digest};
}

#######################################################################
# Modtimes

sub newest {
    my %params = (filenames => [],	# Array ref of files to be dated
		  @_);
    # Return the most recent modtime of the list of files
    # If one of them doesn't exist, return undef

    my $newest = undef;
    my $filename = shift;
    foreach my $depfile (@{$params{filenames}}) {
	my $omtime = (stat($depfile))[9];
	if (!defined $omtime) {
	    $newest = $filename = undef;
	    last;
	}
	if (!defined $newest || $omtime>$newest) {
	    $newest = $omtime;
	    $filename = $depfile;
	}
    }
    return ($newest, $filename) if wantarray;
    return $newest;
}

#######################################################################
1;
__END__

=pod

=head1 NAME

Make::Cache::Hash - Dependency file functions and hashing

=head1 SYNOPSIS

Make::Cache::Hash::clear_cache();

hash{tgt}{dep} = Make::Cache::Hash::dfile_read(filename=>I<fn>);

my $digest = Make::Cache::Hash::hash(filenames=>[], text=>[]);

=head1 DESCRIPTION

Make::Cache::Hash contains functions for reading and writing make.d files,
and for doing MD5 hashes on files.

=head1 FUNCTIONS

=over 4

=item dfile_read (filename=>I<in>)

Read the specified filename.  Return a hash reference, where the keys of the
hash are the target (generated output) files, and the values are a hash of
the dependent (required input) files.  The filename itself is considered a
output dependency.

=item hash

Return a MD5 hash on the specified list of filenames, and specified list of
text.  With the ignore_rcs parameter, which defaults as on, ignore any
RCS/CVS/Perforce meta tags in the source.

=item clear_hash

Clear the internal cache used to accelerate the hash() function.  Must be
called anytime a file that has been hashed has changed.

=item newest

Return the mod time of the newest filename in the list of filenames passed.
If any does not exist, return undef.

=back

=head1 SEE ALSO

C<Make::Cache>

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################
