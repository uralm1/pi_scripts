#!/usr/bin/perl
use Mojolicious::Lite -signatures;
use POSIX qw(strftime);
use Fcntl qw(:flock);
use Proc::ProcessTable;

# Documentation browser under "/perldoc"
#plugin 'PODRenderer';

app->mode('production');
app->log->level('info');
app->secrets(['efhthcdjfibvigfjdj']);

plugin 'Config' => { file => 'vv.conf' };
delete app->defaults->{config}; # safety - don't pass passwords to stashes

# run daemon for reverse proxing: MOJO_REVERSE_PROXY=1 vv.pl daemon -m production -p -l http://127.0.0.1:3000
# rewrite base url to deploy in pdir subdirectory
hook(before_dispatch => sub($c) {
  my $url = $c->req->url;
  my $base = $url->base;
  push @{$base->path->trailing_slash(1)}, Mojo::Path->new($c->pdir)->leading_slash(0);
  shift @{$url->path->leading_slash(0)};
}) if $ENV{MOJO_REVERSE_PROXY};

helper purlpath => sub($c, $dir) { Mojo::URL->new($c->config->{program_url})->path($dir) };
helper urlfile => sub($c, $dir, $file) {
  my $u = Mojo::URL->new($dir);
  $u->path->trailing_slash(1);
  $u->path($file);
};
helper pdir => sub($c) { $c->config->{program_dir_url} };
helper MAX_EVENTS_DAY => sub($) { 100 };

helper npreview => sub($, $file) {
  $file =~ s/^(.+)\.jpg$/$1_preview.jpg/;
  return $file;
};

get '/' => sub($c) {
  for my $cam (@{$c->config->{cams}}) {
    read_cam_directories($cam);
  }
  #say Mojo::Util::dumper $c->config->{cams};
  $c->render(template => 'index');
} => 'index';

get '/events' => sub($c) {
  my %dfh;
  my $dh;
  my $cnt = 0;
  opendir($dh, $c->config->{motion_dir}) or return $c->render(text => 'Чтение каталога - Ошибка!');
  while (readdir $dh) {
    if (m#^(\d{2,})-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})-(\d{2,})\.jpg$#) {
      #say $_ . " $1 - $2 $3 $4 $5 $6 $7 - $8";
      my $k = "$2$3$4";
      $dfh{$k} = { info => "$4.$3.$2" } unless defined $dfh{$k};
      $dfh{$k}{"$2$3$4$5$6$7$1"} = {
	file => $_,
	info => "$5:$6:$7 $4.$3.$2 - $1",
      };
      $cnt++;
    }
  }
  closedir($dh);
  $c->render(template => 'events', dfh => \%dfh, dp => $c->param('d'), total => $cnt);
};

# /ev/0 .. /ev/99 events pages
get '/ev/:camid' => [camid => qr/\d{1,2}/] => sub($c) {
  my $cam = $c->config->{cams}[$c->param('camid')];
  return $c->render(text => 'Ошибка!') unless $cam;
  read_cam_directories($cam);

  $c->render(template => 'ev', dfh => $cam->{dfh}, camid => $c->param('camid'), dp => $c->param('d'), total => $cam->{totalev});
};

# /st/0 .. /st/9 stream pages
get '/st/:camid' => [camid => qr/\d/] => sub($c) {
  my $cam = $c->config->{cams}[$c->param('camid')];
  return $c->render(text => 'Ошибка!') unless $cam && $cam->{streamcam};

  my $restreamer_pid = check_restreamer($cam->{restreamer});
  $c->render(template => 'st', camid => $c->param('camid'), restreamer_pid => $restreamer_pid);
};

# /ffctl/0 .. /ffctl/9 start/stop restreamer
get '/ffctl/:camid' => [camid => qr/\d/] => sub($c) {
  my $cam = $c->config->{cams}[$c->param('camid')];
  return $c->render(text => 'Ошибка!') unless $cam && $cam->{streamcam};

  my $start = $c->param('start');
  my $stop = $c->param('stop');
  my $pid;
  if (defined $stop && $stop) {
    $pid = check_restreamer($cam->{restreamer});
    return $c->render(text => 'ERR STOP, ALREADY STOPPED!') unless $pid;
    return $c->render(text => "TODO STOP PID: $pid!");
  } elsif (defined $start && $start) {
    $pid = check_restreamer($cam->{restreamer});
    return $c->render(text => "ERR START, ALREADY STARTED PID: $pid!") if $pid;
    return $c->render(text => 'TODO START!');
  } else {
    return $c->render(text => 'Ошибка!');
  }
};


app->start;
exit 0;


sub read_cam_directories($cam) {
  my (%s, %dfh, $tot);
  if ($cam->{dir_recursive}) {
    $tot = process_recursive($cam->{dir}, '',
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \%s, \%dfh);
  } else {
    $tot = process_nr($cam->{dir},
      $cam->{shot_regex}, $cam->{eventcam} ? $cam->{motion_regex} : undef, \%s, \%dfh);
  }
  $cam->{sf} = \%s; # $s{file} can be undef
  $cam->{dfh} = \%dfh;
  $cam->{totalev} = $tot;
}

sub process_nr($dir, $shot_re, $motion_re, $s_ref, $dfh_ref) {
  opendir(my $dh, $dir) or die "$dir opendir failed";

  $s_ref->{file} = '' unless defined $s_ref->{file};
  my $mcnt = 0;
  while (readdir $dh) {
    my $p = "$dir/$_";
    if (-f $p) {
      #say $p;
      next if check_locked($p);
      next if m#preview\.jpg$#;
      my $mtime = get_file_mtime($p);
      if (m#$shot_re#) {
        if (($_ cmp $s_ref->{file}) > 0) {
	  $s_ref->{file} = $_;
	  $s_ref->{info} = humaninfo($_, $mtime);
	}
      } elsif (defined($motion_re) && m#$motion_re#) {
	next unless defined $mtime;
	my $k = YMDkey($mtime);
        $dfh_ref->{$k} = { info => humanDMY($mtime) } unless defined $dfh_ref->{$k};
        $dfh_ref->{$k}{$_} = {
	  file => $_,
	  info => humaninfo($_, $mtime),
        };
        ++$mcnt;
      }# else { say "Invalid $p"; }
    }
  }

  closedir($dh);
  $s_ref->{file} = undef if $s_ref->{file} eq '';
  return $mcnt;
}

sub process_recursive($dir, $subdir, $shot_re, $motion_re, $s_ref, $dfh_ref) {
  my $fulldir = $dir;
  $fulldir .= '/'.$subdir unless $subdir eq '';

  opendir(my $dh, $fulldir) or die "$fulldir opendir failed";

  $s_ref->{file} = '' unless defined $s_ref->{file};
  my $mcnt = 0;
  while (readdir $dh) {
    my $p = "$fulldir/$_";
    my $subp = $subdir eq '' ? $_ : "$subdir/$_";
    if (-f $p) {
      #say $p;
      next if check_locked($p);
      next if m#preview\.jpg$#;
      my $mtime = get_file_mtime($p);
      if (m#$shot_re#) {
        if (($subp cmp $s_ref->{file}) > 0) {
          $s_ref->{file} = $subp;
	  $s_ref->{info} = humaninfo($subp, $mtime);
	}
      } elsif (defined($motion_re) && m#$motion_re#) {
	next unless defined $mtime;
	my $k = YMDkey($mtime);
        $dfh_ref->{$k} = { info => humanDMY($mtime) } unless defined $dfh_ref->{$k};
        $dfh_ref->{$k}{$subp} = {
	  file => $subp,
	  info => humaninfo($subp, $mtime),
        };
        ++$mcnt;
      }# elsif (!m#^DVR#) {
	#say "Invalid $p";
      #}
    } elsif (-d $p && m#^[^.]#) {
      $mcnt += process_recursive($dir, $subp, $shot_re, $motion_re, $s_ref, $dfh_ref);
    }
  }

  closedir($dh);
  $s_ref->{file} = undef if $s_ref->{file} eq '';
  return $mcnt;
}

sub get_file_mtime($file) {
  return (stat($file))[9];
}

sub YMDkey($epoch) {
  return strftime('%Y%m%d', localtime($epoch));
}

sub humanDMY($epoch) {
  return strftime('%d.%m.%Y', localtime($epoch));
}

sub humaninfo($file, $epoch) {
  my $humantime = defined $epoch ? strftime('%H:%M:%S %d.%m.%Y', localtime($epoch)) : '<нет данных>';
  my $fileid = ($file =~ m#^(.*[a-z/])?([^/]+)\.jpg$#) ? $2 : '';
  return "$humantime $fileid";
}

sub check_locked($file) {
  open(my $fh, '<', $file) or return 1;
  if (flock($fh, LOCK_SH | LOCK_NB)) {
    flock($fh, LOCK_UN);
    close($fh);
    return 0;
  }
  close($fh);
  return 1;
}


sub check_restreamer($cmd) {
  my $pt = Proc::ProcessTable->new('enable_ttys' => 0, 'cache_ttys' => 0);

  my @r = grep {$_->cmndline eq $cmd} @{$pt->table};

  return undef unless @r;
  return $r[0]->pid;
}


__DATA__

@@ index.html.ep
% title 'Видеонаблюдение';
% layout 'default';
% my $idx;
% while (($idx, $_) = each @{config->{cams}}) {
<p><b><%= $_->{name} %></b>
% if ($_->{streamcam}) {
%== link_to 'Видеопоток' => url_for('stcamid', camid => $idx) => (class => 'camlink')
% }
% if ($_->{eventcam}) {
%== link_to "События" => url_for('evcamid', camid => $idx) => (class => 'camlink')
% }
</p>
% if (my $f = $_->{sf}{file}) {
<div class="ev"><%= $_->{sf}{info} =%><br>
<a href="<%== urlfile($_->{dir_url}, $f) %>"><img class="shp" src="<%== $_->{snapshot_preview_url} %>" alt="<%== $f %>"></a>
</div>
% } else {
Файл камеры отсутствует<br>
% }
% }


@@ events.html.ep
% title 'События';
% layout 'default';
<p><b>События</b>
<span class="camlink"><%== $total %> файлов</span>
%== link_to 'Возврат к камерам' => 'index' => (class => 'camlink')
<br>
% my $firstkey;
% my $dp_ok;
% foreach (sort { $b cmp $a } keys %{$dfh}) {
%   $firstkey = $_ unless defined $firstkey;
%   $dp_ok = 1 if defined $dp && $dp eq $_;
%== link_to $dfh->{$_}{info} => url_for('events')->query(d => $_) => (class => 'daylink')
% }
</p>
% $firstkey = 'none' unless defined $firstkey;
% my $cur = ($dp_ok) ? $dp : $firstkey;
% my $c = 1;
% foreach (sort { $b cmp $a } keys %{$dfh->{$cur}}) {
%   next if $_ eq 'info';
%   if ($c > MAX_EVENTS_DAY) {
<div class="ev">Внимание! Остальные события не показаны</div>
%     last;
%   }
%   my $fhref = $dfh->{$cur}->{$_};
%   my $f = $fhref->{file};
<div class="ev"><%= $fhref->{info} =%><br>
% my $md = config->{motion_dir_url};
%== link_to image(urlfile($md, npreview($f)), alt => 'Event '.$fhref->{info}, (class => 'evp')) => urlfile($md, $f)
</div>
%   ++$c;
% }

@@ ev.html.ep
% title 'События';
% layout 'default';
% my $cam = config->{cams}[$camid];
<p><b>События - <%= $cam->{name} %></b><br>
<span class="camlink"><%== $total %> файлов</span>
%== link_to 'Возврат к камерам' => 'index' => (class => 'camlink')
<br>
% my $firstkey;
% my $dp_ok;
% for (sort { $b cmp $a } keys %{$dfh}) {
%   $firstkey = $_ unless defined $firstkey;
%   $dp_ok = 1 if defined $dp && $dp eq $_;
%== link_to $dfh->{$_}{info} => url_for('evcamid', camid => $camid)->query(d => $_) => (class => 'daylink')
% }
</p>
% $firstkey = 'none' unless defined $firstkey;
% my $cur = ($dp_ok) ? $dp : $firstkey;
% my $c = 1;
% for (sort { $b cmp $a } keys %{$dfh->{$cur}}) {
%   next if $_ eq 'info';
%   if ($c > MAX_EVENTS_DAY) {
<div class="ev">Внимание! Остальные события не показаны</div>
%     last;
%   }
%   my $fhref = $dfh->{$cur}->{$_};
%   my $f = $fhref->{file};
<div class="ev"><%= $fhref->{info} =%><br>
% my $d = $cam->{dir_url};
%== link_to image(urlfile($d, npreview($f)), alt => 'Event '.$fhref->{info}, (class => 'evp')) => urlfile($d, $f)
</div>
%   ++$c;
% }

@@ st.html.ep
% title 'Видеопоток';
% layout 'default';
<script src="<%== pdir %>/css/hls.min.js"></script>
% my $cam = config->{cams}[$camid];
<p><b>Видеопоток - <%= $cam->{name} %></b><br>
%== link_to 'Возврат к камерам' => 'index' => (class => 'camlink')
</p>
<p>Рестример:
% if (defined $restreamer_pid) {
<span class="tgreen">работает (<%= $restreamer_pid %>)</span>.
%== link_to 'Остановить' => url_for('ffctlcamid', camid => $camid)->query(stop => 1)
% } else
<span class="tred">не запущен</span>.
%== link_to 'Запустить' => url_for('ffctlcamid', camid => $camid)->query(start => 1)
% }
</p>
<video id="hls-video" width="<%== $cam->{width} %>" height="<%== $cam->{height} %>" controls muted autoplay></video>
<script>
function initHlsPlayer() {
  const video = document.getElementById('hls-video');
  const hlsUrl = '<%== $cam->{stream_url} %>';
  if (Hls.isSupported()) {
    const hls = new Hls({
      debug: false,
      liveDurationInfinity: true,
      enableWorker: true,
      lowLatencyMode: true,
      backBufferLength: 90
    });
    hls.loadSource(hlsUrl);
    hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, function() {
      video.play();
    });
    hls.on(Hls.Events.ERROR, function(event, data) {
      console.error('Hls error:', data);
    });
  } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = hlsUrl;
    //video.addEventListener('loadedmetadata', function() {video.play()});
  } else {
    alert('Browser does not support Hls video');
  }
}
document.addEventListener('DOMContentLoaded', initHlsPlayer);
</script>


@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8"/>
  <meta http-equiv="X-UA-Compatible" content="IE=Edge">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= title %></title>
  <!--link rel="shortcut icon" href="<%== pdir %>/img/favicon.png"-->
  <link rel="stylesheet" href="<%== pdir %>/css/v.css@2">
</head>
<body>
<%= content %>
</body>
</html>
