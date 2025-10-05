# -*- perl -*-

package Ural::evr;

use strict;
use warnings;
use v5.16;
use feature 'signatures';

use Carp;
use File::Spec;
use File::Path;
use IO::Dir;
use IO::LockedFile;
#use Sys::Syslog;
use Image::Magick;
use WWW::Telegram::BotAPI;
#use Data::Dumper;

my $ftp_root = '/tmp/ftproot';
my $debug_print_enabled = 1;

my $cams = [
{ dir => 'cam/c2', # relative to $ftp_root
  dir_recursive => 1,
  shot_regex => qr#^.*\[R\].*\.jpg$#,
  motion_regex => qr#^.*\[M\].*\.jpg$#,
  eventcam => 1,
  keep_num => 80,
},
{ dir => 'cam',
  dir_recursive => 0,
  shot_regex => qr#^.*shot.*\.jpg$#,
  motion_regex => qr#^.*motion.*\.jpg$#,
  eventcam => 1,
  keep_num => 20,
},
];

sub debug_print($str) {
  say STDERR $str if $debug_print_enabled;
}


sub create_directories() {
  for (@$cams) {
    File::Path::make_path(File::Spec->catdir($ftp_root, $_->{dir}), {chmod => 0777});
  }
}

sub check_directories($root_dir) {
  for (@$cams) {
    my $dir = File::Spec->catdir($root_dir, $ftp_root, $_->{dir});
    unless(-d $dir) {
      croak "$dir directory doesn't exist!";
    }
  }
}

sub handle_file_store($file) {
  return unless $file;
  # $file can come in following variants:
  # file.jpg
  # /cam/c2/2024-01-01/001/jpg/file.jpg
  # so, first try to cut $cam->{dir} at the beginning of $file

  for my $cam (@$cams) {
    my $fixed_file = $file;
    my $fixed_camdir = File::Spec->catdir('/', $cam->{dir});
    if (index($fixed_file, $fixed_camdir) == 0) {
      substr($fixed_file, 0, length($fixed_camdir), '');
    }
    $fixed_file =~ s{^/+}{};
    debug_print "file argument fixed: $fixed_file";

    clean_cam_directories($cam, $fixed_file);
  }
}


sub clean_cam_directories($cam, $file_arg) {
  my (@s, @m);
  if ($cam->{dir_recursive}) {
    process_recursive(File::Spec->catdir($ftp_root, $cam->{dir}), '',
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \@s, \@m);
  } else {
    process_nr(File::Spec->catdir($ftp_root, $cam->{dir}),
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \@s, \@m);
  }
  ###debug_print Dumper(\@s, \@m);
  # clean up shots
  my $c = 1;
  for my $f (sort {$b cmp $a} @s) {
    #debug_print $f;
    my $ff = untaint( File::Spec->catfile($ftp_root, $cam->{dir}, $f) );
    if ($c > 1 && $f ne $file_arg) {
      debug_print "unlinking $ff, ".npreview($ff);
      unlink $ff;
      unlink npreview($ff);
    }
    ++$c;

    # generate preview for shot
    if ($f eq $file_arg) {
      debug_print "generating shot preview for $ff";
      make_preview($ff, '640x360');
    }
  }

  # clean up motions
  $c = 1;
  for my $f (sort {$b cmp $a} @m) {
    #debug_print $f;
    my $ff = untaint( File::Spec->catfile($ftp_root, $cam->{dir}, $f) );
    if ($c > $cam->{keep_num}) {
      debug_print "unlinking $ff, ".npreview($ff);
      unlink $ff;
      unlink npreview($ff);
    }
    ++$c;

    # generate preview for motion
    if ($f eq $file_arg) {
      debug_print "generating motion preview for $ff";
      make_preview($ff, '320x180');
    }
  }
}

sub process_nr($dir, $shot_re, $motion_re, $s_ref, $m_ref) {
  my $dh = IO::Dir->new($dir) or croak "$dir opendir failed";

  my $cnt = 0;
  while (defined($_ = $dh->read)) {
    my $p = "$dir/$_";
    if (-f $p) {
      #debug_print $p;
      next if m#preview\.jpg$#;
      if (m#$shot_re#) {
	push @$s_ref, $_;
      } elsif (defined($motion_re) && m#$motion_re#) {
	push @$m_ref, $_;
        ++$cnt;
      } else { 
	debug_print "Invalid $p, deleting it";
	unlink untaint($p);
      }
    }
  }

  undef $dh;
  return $cnt;
}

sub process_recursive($dir, $subdir, $shot_re, $motion_re, $s_ref, $m_ref) {
  my $fulldir = $dir;
  $fulldir .= '/'.$subdir unless $subdir eq '';

  my $dh = IO::Dir->new($fulldir) or croak "$fulldir opendir failed";

  my $cnt = 0;
  while (defined($_ = $dh->read)) {
    my $p = "$fulldir/$_";
    my $subp = $subdir eq '' ? $_ : "$subdir/$_";
    if (-f $p) {
      #debug_print $p;
      next if m#preview\.jpg$#;
      if (m#$shot_re#) {
        push @$s_ref, $subp;
      } elsif (defined($motion_re) && m#$motion_re#) {
        push @$m_ref, $subp;
        ++$cnt;
      } elsif (!m#^DVR#) {
	debug_print "Invalid $p, deleting it";
	unlink untaint($p);
      }
    } elsif (-d $p && m#^[^.]#) {
      $cnt += process_recursive($dir, $subp, $shot_re, $motion_re, $s_ref, $m_ref);
    }
  }

  undef $dh;
  return $cnt;
}


sub untaint($data) {
  if ($data =~ /(.*)/) {
    return $1;
  } else {
    die 'Died horrible in untaint';
  }
}

sub npreview($file) {
  $file =~ s/^(.+)\.jpg$/$1_preview.jpg/;
  return $file;
}

# make_preview('/tmp/motion/rrr.jpg', '640x360');
sub make_preview($file, $geom) {
  my $image = Image::Magick->new;
  # strange bug here: long filepathes got corrupted in Read so use fd
  my $fh = IO::LockedFile->new({block=>1,lock=>1}, $file, 'r');
  my $r = $image->Read(file=>\*$fh);
  debug_print "Read returned $r" if $r;
  undef $fh;
  $image->Thumbnail(geometry=>$geom);
  $image->UnsharpMask(radius=>0, sigma=>.5);
  $r = $image->Write(npreview($file));
  debug_print "Write returned $r" if $r;
  undef $image;
}

1;
__END__
