#!/usr/bin/make -f
#

default :
	@echo "Please use: \"make install\" to install package."

install : install-ddns install-motion install-vv install-openhab install-udev

DDNS_DESTDIR = /opt/ddns
MOTION_CONFDIR = /etc/motion
VV_DESTDIR = /var/www/vv
OH_CONFDIR = /etc/openhab
UDEV_RULESDIR = /etc/udev/rules.d

install-ddns :
	@echo "Installing ddns..."
	install -m 0755 -d $(DDNS_DESTDIR)
	install -m 0755 ddns/u_v6 ddns/i_test $(DDNS_DESTDIR)
	install -m 0644 ddns/ddns.cron /etc/cron.d/ddns
	install -m 0644 ddns/refresh.cron /etc/cron.d/ddns_refresh
	install -m 0644 ddns/i_test.cron /etc/cron.d/i_test
	@F="ddns.conf"; if [ -f ddns/$$F ]; then install -m 0644 ddns/$$F $(DDNS_DESTDIR); else echo "WARN: No $$F file found! Empty configuration file is installed."; install -m 0644 ddns/$${F}_empty $(DDNS_DESTDIR)/$$F; fi
	install -m 0755 ddns/reboot_modem ddns/e_rebooter $(DDNS_DESTDIR)
	install -m 0644 ddns/e_rebooter.cron /etc/cron.d/e_rebooter

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

install-openhab :
	@echo "Installing openhab..."
	install -m 0664 -o openhab -g openhab openhab/items/*.items $(OH_CONFDIR)/items
	install -m 0664 -o openhab -g openhab openhab/persistence/*.persist $(OH_CONFDIR)/persistence
	install -m 0664 -o openhab -g openhab openhab/rules/*.rules $(OH_CONFDIR)/rules
	install -m 0664 -o openhab -g openhab openhab/services/addons.cfg $(OH_CONFDIR)/services
	for F in rlog; do install -m 0755 openhab/services/$$F $(OH_CONFDIR)/services; done
	install -m 0664 -o openhab -g openhab openhab/sitemaps/*.sitemap $(OH_CONFDIR)/sitemaps
	install -m 0664 -o openhab -g openhab openhab/things/*.things $(OH_CONFDIR)/things
	for F in div*.js sw_ping.map; do install -m 0664 -o openhab -g openhab openhab/transform/$$F $(OH_CONFDIR)/transform; done
	install -m 0755 -o openhab -g openhab -d $(OH_CONFDIR)/misc
	install -m 0664 -o openhab -g openhab openhab/misc/exec.whitelist $(OH_CONFDIR)/misc
	install -m 0775 -o openhab -g openhab openhab/misc/*.sh $(OH_CONFDIR)/misc

install-udev :
	@echo "Installing udev rules..."
	install -m 0644 udev/*.rules $(UDEV_RULESDIR)

