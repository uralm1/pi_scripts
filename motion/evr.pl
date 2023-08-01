#!/usr/bin/perl
# usage: evr.pl /tmp/motion/rrr.jpg

#BEGIN { $ENV{'TELEGRAM_BOTAPI_DEBUG'} = 1; }

use v5.12;
use strict;
use warnings;
use utf8;

use Image::Magick;
use WWW::Telegram::BotAPI;
use File::Basename;
#use Data::Dumper;

my $ev_dir = '/tmp/motion';
my $snapshot1 = 'c1_shot.jpg';
my $snapshot2 = 'c2_shot.jpg';
my $keep_num = 120;
my $timestamp_file = "$ev_dir/telegram.timestamp";
my $telegram_config = '/etc/openhab2/services/telegram.cfg';
my $telegram_token;
my $chat_id;

my $f = shift or exit 0;

if ($f eq "$ev_dir/$snapshot1") {
  #say "snapshot1 processing";
  make_preview($f, '640x360');
} elsif ($f eq "$ev_dir/$snapshot2") {
  #say "snapshot2 processing";
  make_preview($f, '640x360');
} elsif ($f =~ m#^$ev_dir/\d{2,}-\d{14}-\d{2,}\.jpg$#) {
  #say "event processing";
  my $fp = make_preview($f, '320x180');
  cleanup_dir();
  my ($min, $hour) = (localtime)[1,2];
  send_telegram($fp) if $hour >= 9 && $hour < 22;
}

exit 0;

# make_preview('/tmp/motion/rrr.jpg', '640x360');
sub make_preview {
  my $file = shift or die "Required filename missing";
  my $geom = shift or die "Required size missing";

  my $image = Image::Magick->new;
  $image->Read($file);
  $image->Thumbnail(geometry=>$geom);
  $image->UnsharpMask(radius=>0, sigma=>.5);
  $file =~ s/^(.+)\.jpg$/$1_preview.jpg/;
  $image->Write($file);
  undef $image;
  return $file;
}

# cleanup_dir();
sub cleanup_dir {
  my %ffh;
  opendir(my $dh, $ev_dir) or return 1;
  while (readdir $dh) {
    #if (m#^(\d{2,})-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})-(\d{2,})\.jpg$#) {
    if (m#^(\d{2,})-(\d{14})-\d{2,}\.jpg$#) {
      #say $_ . " $1 - $2 $3 $4 $5 $6 $7 - $8";
      $ffh{$2.$1} = {
	file => $_,
	#ev => $1,
	#year => $2,
	#month => $3,
	#day => $4,
	#hour => $5,
	#min => $6,
	#sec => $7
      };
    }
  }
  closedir($dh);

  my $c = 1;
  foreach (sort { $b cmp $a} keys %ffh) {
    #say $_;
    if ($c > $keep_num) {
      my $file = $ev_dir.'/'.$ffh{$_}{file};
      unlink $file;
      $file =~ s/^(.+)\.jpg$/$1_preview.jpg/;
      unlink $file;
    }
    $c++;
  }
  return 0;
}

# send_telegram('/tmp/motion/rrr_preview.jpg');
sub send_telegram {
  my $file = shift or die "Required filename missing";
  my $old_timestamp;
  if (open(my $fh, '<', $timestamp_file)) {
    local $/;
    $old_timestamp = <$fh>;
    close $fh or say 'Timestamp file close failure';
  }
  $old_timestamp //= 0;
  my $t = time;
  return if $t - $old_timestamp < 3600;

  if (open(my $fh, '<', $telegram_config)) {
    while (<$fh>) {
      if (!defined $chat_id && m/^\S+\.chatId\s*=\s*["']?([A-Za-z0-9:-]+)["']?$/xi) {
        $chat_id = $1;
      } elsif (!defined $telegram_token && m/^\S+\.token\s*=\s*["']?([A-Za-z0-9:-]+)["']?$/xi) {
        $telegram_token = $1;
      }
    }
    close $fh or say 'Telegram configuration file close failure';
    unless (defined $telegram_token && defined $chat_id) {
      say "Telegram configuration file $telegram_config doesn't include correct token or chat_id";
      return;
    }
  } else {
    say "Telegram configuration file $telegram_config doesn't exist.";
    return;
  }
  my $api = WWW::Telegram::BotAPI->new(token => $telegram_token);
  
  my $file_name = basename $file;
  if (-r $file && $file_name =~ m#^(\d{2,})-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})-(\d{2,})_preview\.jpg$#) {
    #say "$1 - $2 $3 $4 $5 $6 $7 - $8";
    my $r = eval { $api->sendPhoto({ chat_id => $chat_id, photo => { file => $file }, caption => "$5:$6:$7 $4.$3.$2" }) };
    say 'sendPhoto error: '.$api->parse_error->{msg} unless $r;
  } else {
    my $r = eval { $api->sendMessage({ chat_id => $chat_id, text => "Не обработал $file_name." }) };
    say 'sendMessage error: '.$api->parse_error->{msg} unless $r;
  }
  undef $api;

  if (open(my $fh, '>', $timestamp_file)) {
    print $fh $t;
    close $fh or say 'Timestamp file close failure';
  } else {
    say "Error updating timestamp file: $!";
  }
}
