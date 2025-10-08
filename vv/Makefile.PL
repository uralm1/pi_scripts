use strict;
use warnings;

use ExtUtils::MakeMaker;

my $inst_dir = '/var/www/vv';

WriteMakefile(
  NAME => 'Vv',
  AUTHOR => 'Ural Khasanov <email>',
  DISTNAME => 'vv',
  VERSION => '1.0',
  PREREQ_PM => {
    'Mojolicious' => '8.50',
  },
  #test      => {TESTS => 't/*.t'},
  PREFIX => $inst_dir,
  LIB => "$inst_dir/lib",
  PMLIBDIRS => ['lib'],
  PM => {},
  INSTALLSCRIPT => "$inst_dir/",
  INSTALLSITESCRIPT => "$inst_dir/",
  EXE_FILES => ['vv.pl'],
  MAN1PODS => {},
  MAN3PODS => {},
);

package MY;
sub install {
  my $inherited = shift->SUPER::install(@_);
  return $inherited.<<"MAKE_FRAG";
install::
	\$(NOECHO) \$(ECHO) "** Installing configuration and css files..."
	\$(NOECHO) install -m 0644 vv.conf_empty \$(DESTDIR)$inst_dir/vv.conf_empty
	\$(NOECHO) install -m 0755 -d \$(DESTDIR)$inst_dir/css
	\$(NOECHO) install -m 0644 css/v.css \$(DESTDIR)$inst_dir/css/v.css

MAKE_FRAG
}

sub postamble {
  return <<'MAKE_FRAG';
all::
	$(NOECHO) $(ECHO) "** Checking..."
	$(NOECHO) if ! grep -q -e "^\s*app->mode(['\"]production['\"])" vv.pl ; then echo "\nWARNING! Production mode in vv.pl is NOT enabled!\n"; fi
	$(NOECHO) if ! grep -q -e "^\s*app->log->level(['\"]info['\"])" vv.pl ; then echo "\nWARNING! Log level in vv.pl is NOT info!\n"; fi

MAKE_FRAG
}

