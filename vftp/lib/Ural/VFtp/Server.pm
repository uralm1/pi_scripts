# -*- perl -*-

=pod

=head1 NAME

Ural::VFtp::Server - VFtp Net::FTPServer personality

=head1 SYNOPSIS

See vftp.pl

=head1 DESCRIPTION

=head1 METHODS

=cut

package Ural::VFtp::Server;

use strict;

use vars qw($VERSION);
( $VERSION ) = '$Revision: 1.0 $ ' =~ /\$Revision:\s+([^\s]+)/;

use Net::FTPServer;
use Ural::VFtp::FileHandle;
use Ural::VFtp::DirHandle;

use Ural::evr;

use vars qw(@ISA);
@ISA = qw(Net::FTPServer);

=pod

=over 4

=item $self->post_configuration_hook;

=cut

sub post_configuration_hook {
  my $self = shift;
  Ural::evr::get_evr_configuration($self);
  Ural::evr::check_directories($self);
}

=pod

=item $rv = $self->authentication_hook($user, $pass, $user_is_anon)

Perform login (anonymous only).

=cut

sub authentication_hook {
  my ($self, $user, $pass, $user_is_anon) = @_;

  # Only allow anonymous users.
  return -1 unless $user_is_anon;

  return 0;
}

=pod

=item $self->user_login_hook($user, $user_is_anon)

Hook: Called just after user C<$user> has successfully logged in.

=cut

sub user_login_hook {
  my ($self, $user, $user_is_anon) = @_;

  # For anonymous users, chroot to ftp directory.
  my ($login, $pass, $uid, $gid, $quota, $comment, $gecos, $homedir) = getpwnam "ftp"
    or die "no ftp user in password file";

  my $root_directory = $self->config("root directory");
  die "root directory is not set in configuration file" unless defined $root_directory;

  die "currently we don't do chroot, so root directory must be '/'" if $root_directory ne '/';
  #if ($< == 0) {
  #  chroot $root_directory or die "cannot chroot: $root_directory: $!";
  #} else {
  #  chroot $root_directory or die "cannot chroot: $root_directory: $!"
  #    . " (you need root privilege to use chroot feature)";
  #}

  my $home_directory = $self->config("home directory");
  die "home directory is not set in configuration file" unless defined $home_directory;

  $self->{home_directory} = $home_directory;

  # We don't allow users to relogin, so completely change to the user specified.
  $self->_drop_privs($uid, $gid, $login);
}

=pod

=item $dirh = $self->root_directory_hook;

Hook: Return an instance of DirHandle corresponding to the root directory.

=cut

sub root_directory_hook {
  my $self = shift;
  return Ural::VFtp::DirHandle->new($self);
}


=pod

=item $self->post_command_hook($cmd, $rest);

=cut

sub post_command_hook {
  my ($self, $cmd, $rest) = @_;

  ###$self->log('info', "- $cmd: $rest -");

  #STOR, STOU, APPE commands modifies fs, but we only handle STOR
  if ($cmd eq 'STOR') {
    Ural::evr::handle_file_store($rest);
  }
}

1;
__END__

=back

=head1 AUTHORS

=head1 COPYRIGHT

=head1 SEE ALSO

=cut
