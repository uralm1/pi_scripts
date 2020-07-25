#!/usr/bin/make -f
#

default :
	@echo "Please use: \"make install\" to install package."

install : install-ddns install-motion install-vv

DDNS_DESTDIR = /opt/ddns
MOTION_CONFDIR = /etc/motion
VV_DESTDIR = /var/www/vv

install-ddns :
	@echo "Installing ddns..."
	install -m 0755 -d $(DDNS_DESTDIR)
	install -m 0755 ddns/u_v6 ddns/i_test $(DDNS_DESTDIR)
	install -m 0644 ddns/*.cron /etc/cron.d
	@F="ddns.conf"; if [ -f ddns/$$F ]; then install -m 0644 ddns/$$F $(DDNS_DESTDIR); else echo "WARN: No $$F file found! Empty configuration file is installed."; install -m 0644 ddns/$${F}_empty $(DDNS_DESTDIR)/$$F; fi

install-motion :
	@echo "Installing motion..."
	install -m 0755 -d $(MOTION_CONFDIR)
	install -m 0644 motion/motion.conf $(MOTION_CONFDIR)
	install -m 0644 motion/*.pgm $(MOTION_CONFDIR)
	install -m 0755 motion/evr.pl $(MOTION_CONFDIR)
	@F="c1-dlink.conf"; if [ -f motion/$$F ]; then install -m 0644 motion/$$F $(MOTION_CONFDIR); else echo "WARN: No $$F file found! Empty configuration file is installed."; install -m 0644 motion/$${F}_empty $(MOTION_CONFDIR)/$$F; fi
	@F="c2-dahua.conf"; if [ -f motion/$$F ]; then install -m 0644 motion/$$F $(MOTION_CONFDIR); else echo "WARN: No $$F file found! Empty configuration file is installed."; install -m 0644 motion/$${F}_empty $(MOTION_CONFDIR)/$$F; fi

install-vv :
	@echo "Installing vv..."
	install -m 0755 -d $(VV_DESTDIR)
	install -m 0755 -d $(VV_DESTDIR)/css
	install -m 0755 vv/vv.pl $(VV_DESTDIR)
	install -m 0644 vv/css/v.css $(VV_DESTDIR)/css
	@F="vv.conf"; if [ -f vv/$$F ]; then install -m 0644 vv/$$F $(VV_DESTDIR); else echo "WARN: No $$F file found! Empty configuration file is installed."; install -m 0644 vv/$${F}_empty $(VV_DESTDIR)/$$F; fi

