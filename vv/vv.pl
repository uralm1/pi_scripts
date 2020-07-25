#!/usr/bin/perl
use Mojolicious::Lite;

# Documentation browser under "/perldoc"
#plugin 'PODRenderer';

app->mode('production');
app->log->level('info');
app->secrets(['efhthcdjfibvigfjdj']);

plugin 'Config' => { file => 'vv.conf' };
delete app->defaults->{config}; # safety - not to pass passwords to stashes

helper evdir => sub { return shift->config->{event_dir} };
helper pdir => sub { return shift->config->{program_dir_url} };
helper dirurl => sub { return shift->config->{program_url}.'/mv' };
helper max_events_day => sub { return 100 };
helper cams => sub {
  my $c = shift->config;
  my $cr = $c->{cams};
  for (@$cr) { 
    # create streamhtml-s
    $_->{streamhtml} = "<iframe width=\"$_->{width}\" height=\"$_->{height}\" src=\"$c->{program_url}$_->{src}\" frameborder=\"0\" allowfullscreen></iframe>";
  }
  return $cr;
};

helper npreview => sub { shift;
  my $file = shift;
  $file =~ s/^(.+)\.jpg$/$1_preview.jpg/;
  return $file;
};

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
} => 'index';

get '/events' => sub {
  my $c = shift;

  my %dfh;
  my $dh;
  my $cnt = 0;
  opendir($dh, $c->evdir) or return $c->render(text => 'Чтение каталога - Ошибка!');
  while (readdir $dh) {
    if (m#^(\d{2,})-(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})-(\d{2,})\.jpg$#) {
      #say $_ . " $1 - $2 $3 $4 $5 $6 $7 - $8";
      my $k = "$2$3$4";
      $dfh{$k} = { info => "$4.$3.$2" } unless defined $dfh{$k};
      $dfh{$k}{"$2$3$4$5$6$7$1"} = {
	file => $_,
	ev => $1,
	info => "$5:$6:$7 $4.$3.$2 - $1",
      };
      $cnt++;
    }
  }
  closedir($dh);
  $c->render(template => 'events', dfh => \%dfh, dp => $c->param('d'), total => $cnt);
};

# /st/0 .. /st/9 streamer helper
get '/st/:camid' => [camid => qr/\d/] => sub {
  my $c = shift;
  my $h = $c->cams->[$c->param('camid')]->{streamhtml};
  unless ($h) { return $c->render(text => 'Ошибка!'); }
  $c->render(template => 'st', code => $h);
};


app->start;


__DATA__

@@ index.html.ep
% title 'Видеонаблюдение';
% layout 'default';
% foreach (@{cams()}) {
<p><b><%= $_->{name} %></b>
%== link_to 'Видеопоток' => $_->{streampage} => (class => 'camlink')
% if ($_->{eventcam}) {
%== link_to 'События' => 'events' => (class => 'camlink')
% }
</p>
<a href="<%== dirurl.'/'.$_->{snapshotfile} %>"><img class="shp" src="<%== dirurl.'/'.npreview($_->{snapshotfile}) %>" alt="<%== $_->{snapshotfile} %>"></a>
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
%   if ($c > max_events_day) {
<div class="ev">Внимание! Остальные события не показаны</div>
%     last;
%   }
%   my $fhref = $dfh->{$cur}->{$_};
%   my $f = $fhref->{file};
<div class="ev"><%= $fhref->{info} =%><br>
%== link_to image(dirurl.'/'.npreview($f), alt => 'Event'.$fhref->{ev}, (class => 'evp')) => dirurl.'/'.$f
</div>
%   $c++;
% }

@@ st.html.ep
% title 'Видеопоток';
% layout 'default';
%== $code

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8"/>
  <meta http-equiv="X-UA-Compatible" content="IE=Edge">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= title %></title>
  <!--link rel="shortcut icon" href="<%== pdir %>/img/favicon.png"-->
  <link rel="stylesheet" href="<%== pdir %>/css/v.css">
</head>
<body>
<%= content %>
</body>
</html>
