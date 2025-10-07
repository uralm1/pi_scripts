# -*- perl -*-

package Ural::evr;

use strict;
use warnings;
use v5.16;
use feature 'signatures';

use Carp;
use File::Spec;
use File::Path;
use POSIX qw(strftime);
use IO::Dir;
use IO::File;
use IO::LockedFile;
#use Sys::Syslog;
use Image::Magick;
use WWW::Telegram::BotAPI;
#use Data::Dumper;

#BEGIN { $ENV{'TELEGRAM_BOTAPI_DEBUG'} = 1; }

use constant DEBUG_PRINT_ENABLED => 1;

my $cams;
my $telegram_token;
my $chat_id;


sub debug_print($str) {
  say STDERR $str if DEBUG_PRINT_ENABLED;
}

sub error_print($str) {
  say STDERR $str;
}


sub get_evr_configuration($self) {
  my @_cams = $self->config('cams');
  $cams = \@_cams;

  my $telegram_config = $self->config('telegram config');
  my $fh = IO::File->new($telegram_config, 'r');
  unless($fh) {
    error_print "Telegram configuration file $telegram_config doesn't exist. Notifications will not work.";
  } else {
    while (<$fh>) {
      if (!defined $chat_id && m/chatIds\s*=\s*["'][><]?([A-Za-z0-9:-]+)["']/xi) {
	$chat_id = $1;
      }
      if (!defined $telegram_token && m/botToken\s*=\s*["']([A-Za-z0-9:-]+)["']/xi) {
	$telegram_token = $1;
      }
    }
    undef $fh;
    unless (defined $telegram_token && defined $chat_id) {
      error_print "Telegram configuration file $telegram_config doesn't include correct token or chat_id. Notifications will not work.";
    }
  }
}

sub check_directories($self) {
  my $root_dir = $self->config('root directory');
  for (@$cams) {
    my $dir = File::Spec->catdir($root_dir, $_->{dir});

    File::Path::make_path($dir, {chmod => 0777});

    unless(-d $dir) {
      croak "$dir directory doesn't exist!";
    }
  }
}

sub handle_file_store($file) {
  debug_print "STOR command for $file";
  return unless $file;
  # $file can come in following variants:
  # file.jpg
  # /cam/c2/2024-01-01/001/jpg/file.jpg (chrooted to /tmp/ftproot)
  # /tmp/ftproot/cam/c2/2024-01-01/001/jpg/file.jpg (not chrooted)
  # so, first try to cut $cam->{dir} from the beginning of $file

  for my $cam (@$cams) {
    my $fixed_file = $file;
    my $fixed_camdir = File::Spec->catdir('/', $cam->{dir});
    if (index($fixed_file, $fixed_camdir) == 0) {
      substr($fixed_file, 0, length($fixed_camdir), '');
    }
    $fixed_file =~ s{^/+}{};
    debug_print "file argument fixed: $fixed_file (for $cam->{dir})";

    process_cam_directories($cam, $fixed_file);
  }
}


sub process_cam_directories($cam, $file_arg) {
  my (@s, @m);
  if ($cam->{dir_recursive}) {
    process_recursive($cam->{dir}, '',
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \@s, \@m);
  } else {
    process_nr($cam->{dir},
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \@s, \@m);
  }
  ###debug_print Dumper(\@s, \@m);

  # clean up shots
  my $c = 1;
  for my $f (sort {$b cmp $a} @s) {
    #debug_print $f;
    my $ff = untaint( File::Spec->catfile($cam->{dir}, $f) );
    if ($c > 1 && $f ne $file_arg) {
      my $fp = npreview($ff);
      debug_print "unlinking $ff, $fp";
      unlink $ff;
      unlink $fp;
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
    my $ff = untaint( File::Spec->catfile($cam->{dir}, $f) );
    if ($c > $cam->{keep_num}) {
      my $fp = npreview($ff);
      debug_print "unlinking $ff, $fp";
      unlink $ff;
      unlink $fp;
    }
    ++$c;

    # generate preview for motion
    if ($f eq $file_arg) {
      debug_print "generating motion preview for $ff";
      my $fp = make_preview($ff, '320x180');

      if (my $t = check_timestamp($cam->{timestamp_file}, $cam->{notification_interval})) {
	send_telegram( $fp, humaninfo($cam->{name}, get_file_mtime($ff)) );
	update_timestamp($cam->{timestamp_file}, $t);
      }
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

sub get_file_mtime($file) {
  return (stat($file))[9];
}

sub humaninfo($name, $epoch) {
  my $humantime = defined $epoch ? strftime('%H:%M:%S %d.%m.%Y', localtime($epoch)) : '<нет данных>';
  return "$humantime $name";
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
  error_print "Read image returned $r" if $r;
  undef $fh;
  $image->Thumbnail(geometry=>$geom);
  $image->UnsharpMask(radius=>0, sigma=>.5);
  my $fp = npreview($file);
  $r = $image->Write($fp);
  error_print "Write preview returned $r" if $r;
  undef $image;
  return $fp;
}


sub check_timestamp($timestamp_file, $notification_interval) {
  my ($min, $hour) = (localtime)[1,2];
  debug_print "time is $hour:$min";
  return undef unless $hour >= 9 && $hour < 22;
    
  my $old_timestamp;
  if (my $fh = IO::File->new($timestamp_file, 'r')) {
    local $/;
    $old_timestamp = <$fh>;
    undef $fh;
  }
  $old_timestamp //= 0;
  my $t = time;
  return ($t - $old_timestamp < $notification_interval) ? undef : $t;
}

sub update_timestamp($timestamp_file, $time) {
  die unless $time;

  if (my $fh = IO::File->new($timestamp_file, 'w')) {
    print $fh $time;
    undef $fh;
  } else {
    error_print "Error updating timestamp file $timestamp_file: $!";
  }
}

# send_telegram('/tmp/motion/rrr_preview.jpg', 'rrr file');
sub send_telegram($file, $caption) {
  return unless defined $telegram_token && defined $chat_id;

  debug_print "sending notification to telegram for $file";
  my $api = WWW::Telegram::BotAPI->new(token => $telegram_token);

  my $file_name = (File::Spec->splitpath($file))[2]; #basename $file
  if (-r $file) {
    my $r = eval { $api->sendPhoto({ chat_id => $chat_id, photo => { file => $file }, caption => $caption }) };
    debug_print 'sendPhoto error: '.$api->parse_error->{msg} unless $r;
  } else {
    my $r = eval { $api->sendMessage({ chat_id => $chat_id, text => "Не обработал $file_name." }) };
    debug_print 'sendMessage error: '.$api->parse_error->{msg} unless $r;
  }
  undef $api;
}

1;
__END__
