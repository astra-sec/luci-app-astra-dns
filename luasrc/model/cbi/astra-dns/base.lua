local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local m, s, o
local configpath = uci:get("astra-dns", "main", "configpath") or "/etc/astra-dns/named.yaml"
local binpath = uci:get("astra-dns", "main", "binpath") or "/usr/bin/astra-dns"

m = Map("astra-dns", "Astra DNS")
m.description = translate("A lightweight LuCI interface for managing Astra DNS.")
m:section(SimpleSection).template = "astra-dns/status"

s = m:section(TypedSection, "main")
s.anonymous = true
s.addremove = false

s:tab("basic", translate("Basic Settings"))
s:tab("core", translate("Core Settings"))

o = s:taboption("basic", Flag, "enabled", translate("Enable"))
o.default = 0
o.optional = false

local status_html = "<font color=red>" .. translate("No core") .. "</font>"
if fs.access(binpath) then
	local version = sys.exec(binpath .. " --version 2>/dev/null"):gsub("%s+$", "")
	if version ~= "" then
		status_html = "<font color=green>" .. version .. "</font>"
	else
		status_html = "<font color=red>" .. translate("Core error") .. "</font>"
	end
end
if not fs.access(configpath) then
	status_html = status_html .. " " .. "<font color=red>" .. translate("No config") .. "</font>"
end

o = s:taboption("basic", Button, "update", translate("Core"))
o.inputtitle = translate("Install / Update core")
o.template = "astra-dns/update"
o.description = string.format(translate("Core status:") .. " <strong>%s</strong>", status_html)

o = s:taboption("basic", ListValue, "redirect", translate("DNS redirect mode"))
o:value("none", translate("None"))
o:value("redirect", translate("Redirect port 53 to Astra DNS"))
o.default = "none"
o.optional = false

o = s:taboption("basic", Value, "configpath", translate("Config path"))
o.default = "/etc/astra-dns/named.yaml"
o.rmempty = false

o = s:taboption("basic", Value, "logfile", translate("Runtime log file path"))
o.default = "/tmp/astra-dns.log"
o.rmempty = false

o = s:taboption("core", Value, "binpath", translate("Astra DNS executable file path"))
o.default = "/usr/bin/astra-dns"
o.rmempty = false

o = s:taboption("core", Value, "workdir", translate("Work dir"))
o.default = "/var/lib/astra-dns"
o.rmempty = false

o = s:taboption("core", Flag, "verbose", translate("Verbose log"))
o.default = 0
o.optional = false

o = s:taboption("core", Value, "target", translate("Release target"))
o.default = ""
o.placeholder = translate("Auto detect")
o.rmempty = true
o.description = translate("Example: aarch64-unknown-linux-musl")

o = s:taboption("core", TextValue, "downloadlinks", translate("Download links for update"))
o.optional = false
o.rows = 4
o.wrap = "soft"
o.cfgvalue = function()
		return uci:get("astra-dns", "main", "downloadlinks")
			or "https://github.com/astra-sec/astra-dns/releases/latest/download/astra-dns-${Target}.tar.gz"
	end
o.write = function(_, _, value)
		uci:set("astra-dns", "main", "downloadlinks", value:gsub("\r\n", "\n"))
		uci:commit("astra-dns")
	end

return m
