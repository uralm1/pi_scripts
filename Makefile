#!/usr/bin/make -f
#

default :
	@echo "Please use: \"make install\" to install package."

install : install-ddns

DDNS_DESTDIR = /opt/ddns

install-ddns :
	@echo "Installing..."
	install -m 0755 -d $(DDNS_DESTDIR)
	install -m 0644 ddns/ddns.conf $(DDNS_DESTDIR)
	install -m 0755 ddns/u_v6 ddns/i_test $(DDNS_DESTDIR)
	install -m 0644 ddns/*.cron /etc/cron.d

