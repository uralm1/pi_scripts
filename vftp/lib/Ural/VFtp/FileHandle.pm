# -*- perl -*-

=pod

=head1 NAME

Ural::VFtp::FileHandle - VFtp Net::FTPServer personality

=head1 SYNOPSIS

  use Ural::VFtp::FileHandle;

=head1 METHODS

=cut

package Ural::VFtp::FileHandle;

use strict;

use vars qw($VERSION);
( $VERSION ) = '$Revision: 1.0 $ ' =~ /\$Revision:\s+([^\s]+)/;

use IO::LockedFile;
use Time::HiRes qw(usleep);
use Net::FTPServer::FileHandle;

use vars qw(@ISA);

@ISA = qw(Net::FTPServer::FileHandle);

=pod

=over 4

=item $dirh = $fileh->dir;

Return the directory which contains this file.

=cut

sub dir {
  my $self = shift;

  my $dirname = $self->{_pathname};
  $dirname =~ s,[^/]+$,,;

  return Ural::VFtp::DirHandle->new ($self->{ftps}, $dirname);
}

=pod

=item $fh = $fileh->open (["r"|"w"|"a"]);

Open a file handle (derived from C<IO::Handle>, see
C<IO::Handle(3)>) in either read or write mode.

=cut

sub open {
  my ($self, $mode) = @_;

  my $f = IO::LockedFile->new({lock=>0, block=>0}, $self->{_pathname}, $mode);
  for (1..6) {
    last if $f->lock;
    usleep 500000;
  }
  undef $f unless $f->have_lock;
  return $f;
}

=pod

=item ($mode, $perms, $nlink, $user, $group, $size, $time) = $handle->status;

Return the file or directory status. The fields returned are:

  $mode     Mode        'd' = directory,
                        'f' = file,
                        and others as with
                        the find(1) -type option.
  $perms    Permissions Permissions in normal octal numeric format.
  $nlink    Link count
  $user     Username    In printable format.
  $group    Group name  In printable format.
  $size     Size        File size in bytes.
  $time     Time        Time (usually mtime) in Unix time_t format.

In derived classes, some of this status information may well be
synthesized, since virtual filesystems will often not contain
information in a Unix-like format.

=cut

sub status {
  my $self = shift;

  my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
      $atime, $mtime, $ctime, $blksize, $blocks)
    = lstat $self->{_pathname};

  # If the file has been removed since we created this
  # handle, then $dev will be undefined. Return dummy status
  # information.
  return ("f", 0000, 1, "-", "-", 0, 0) unless defined $dev;

  # Generate printable user/group.
  my $user = getpwuid ($uid) || "-";
  my $group = getgrgid ($gid) || "-";

  # Permissions from mode.
  my $perms = $mode & 0777;

  # Work out the mode using special "_" operator which causes Perl
  # to use the result of the previous stat call.
  $mode
    = (-f _ ? 'f' :
       (-d _ ? 'd' :
	(-l _ ? 'l' :
	 (-p _ ? 'p' :
	  (-S _ ? 's' :
	   (-b _ ? 'b' :
	    (-c _ ? 'c' : '?')))))));

  return ($mode, $perms, $nlink, $user, $group, $size, $mtime);
}

=pod

=item $rv = $handle->move ($dirh, $filename);

Move the current file (or directory) into directory C<$dirh> and
call it C<$filename>. If the operation is successful, return 0,
else return -1.

Underlying filesystems may impose limitations on moves: for example,
it may not be possible to move a directory; it may not be possible
to move a file to another directory; it may not be possible to
move a file across filesystems.

=cut

sub move {
  my $self = shift;
  my $dirh = shift;
  my $filename = shift;

  die if $filename =~ /\//;	# Should never happen.

  my $new_name = $dirh->{_pathname} . $filename;

  rename $self->{_pathname}, $new_name or return -1;

  $self->{_pathname} = $new_name;
  return 0;
}

=pod

=item $rv = $fileh->delete;

Delete the current file. If the delete command was
successful, then return 0, else if there was an error return -1.

=cut

sub delete {
  my $self = shift;

  unlink $self->{_pathname} or return -1;

  return 0;
}

=item $link = $fileh->readlink;

If the current file is really a symbolic link, read the contents
of the link and return it.

=cut

sub readlink {
  my $self = shift;

  return readlink $self->{_pathname};
}

1;
__END__

=back

=head1 AUTHORS

=head1 COPYRIGHT

=head1 SEE ALSO

C<Net::FTPServer(3)>, C<perl(1)>

=cut
