use strict;
use warnings;

use ExtUtils::MakeMaker;

my $inst_dir = '/opt/vftp';

WriteMakefile(
  NAME => 'VFtp',
  AUTHOR => 'Ural Khasanov <email>',
  DISTNAME => 'vftp',
  VERSION_FROM => 'lib/Ural/VFtp/Server.pm',
  PREREQ_PM => {
    'Mojolicious' => '8.50',
    'Image::Magick' => 0,
  },
  #test      => {TESTS => 't/*.t'},
  PREFIX => $inst_dir,
  LIB => "$inst_dir/lib",
  PMLIBDIRS => ['lib'],
  PM => {
    'lib/Net/FTPServer.pm' => '$(INST_LIB)/Net/FTPServer.pm',
    'lib/Net/FTPServer/Handle.pm' => '$(INST_LIB)/Net/FTPServer/Handle.pm',
    'lib/Net/FTPServer/DirHandle.pm' => '$(INST_LIB)/Net/FTPServer/DirHandle.pm',
    'lib/Net/FTPServer/FileHandle.pm' => '$(INST_LIB)/Net/FTPServer/FileHandle.pm',
    'lib/Ural/evr.pm' => '$(INST_LIB)/Ural/evr.pm',
    'lib/Ural/VFtp/DirHandle.pm' => '$(INST_LIB)/Ural/VFtp/DirHandle.pm',
    'lib/Ural/VFtp/FileHandle.pm' => '$(INST_LIB)/Ural/VFtp/FileHandle.pm',
    'lib/Ural/VFtp/Server.pm' => '$(INST_LIB)/Ural/VFtp/Server.pm',
    'lib/IO/Scalar.pm' => '$(INST_LIB)/IO/Scalar.pm',
    'lib/IO/LockedFile.pm' => '$(INST_LIB)/IO/LockedFile.pm',
    'lib/IO/LockedFile/Flock.pm' => '$(INST_LIB)/IO/LockedFile/Flock.pm',
    'lib/WWW/Telegram/BotAPI.pm' => '$(INST_LIB)/WWW/Telegram/BotAPI.pm',
  },
  INSTALLSCRIPT => "$inst_dir/",
  INSTALLSITESCRIPT => "$inst_dir/",
  EXE_FILES => ['vftp.pl'],
  MAN1PODS => {},
  MAN3PODS => {},
);

package MY;
sub install {
  my $inherited = shift->SUPER::install(@_);
  return $inherited.<<"MAKE_FRAG";
install::
	\$(NOECHO) \$(ECHO) "** Installing configuration files..."
	\$(NOECHO) install -m 0644 vftp.conf_empty \$(DESTDIR)$inst_dir/vftp.conf_empty

MAKE_FRAG
}
