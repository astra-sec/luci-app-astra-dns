# Copyright (C) 2026
#
# This is free software, licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-astra-dns
PKG_VERSION:=0.0.2
PKG_MAINTAINER:=<https://github.com/astra-sec/luci-app-astra-dns>

LUCI_TITLE:=LuCI app for Astra DNS
LUCI_DEPENDS:=+!wget&&!curl:curl
LUCI_PKGARCH:=all
LUCI_DESCRIPTION:=Lightweight LuCI interface for managing Astra DNS

define Package/$(PKG_NAME)/conffiles
/etc/config/astra-dns
endef

define Package/$(PKG_NAME)/preinst
#!/bin/sh
	uci -q batch <<-EOF >/dev/null 2>&1
		delete ucitrack.@astra_dns[-1]
		add ucitrack astra_dns
		set ucitrack.@astra_dns[-1].init=astra-dns
		commit ucitrack
	EOF
	rm -f /tmp/luci-indexcache
exit 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
	/etc/init.d/astra-dns enable >/dev/null 2>&1
	enable=$(uci get astra-dns.main.enabled 2>/dev/null)
	if [ "$$enable" = "1" ]; then
		/etc/init.d/astra-dns reload >/dev/null 2>&1
	fi
	rm -f /tmp/luci-indexcache
	rm -f /tmp/luci-modulecache/*
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
uci -q batch <<-EOF >/dev/null 2>&1
	delete ucitrack.@astra_dns[-1]
	commit ucitrack
EOF
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
