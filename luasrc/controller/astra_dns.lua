module("luci.controller.astra_dns", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local tmp_config = "/tmp/astra-dns-tmp.yaml"
local tmp_update_log = "/tmp/astra-dns_update.log"
local redirect_state = "/var/run/astra_dns_redirect"

function index()
	entry({"admin", "services", "astra-dns"}, alias("admin", "services", "astra-dns", "base"), _("Astra DNS"), 10).dependent = true
	entry({"admin", "services", "astra-dns", "base"}, cbi("astra-dns/base"), _("Basic Settings"), 1).leaf = true
	entry({"admin", "services", "astra-dns", "manual"}, cbi("astra-dns/manual"), _("Manual Config"), 2).leaf = true
	entry({"admin", "services", "astra-dns", "log"}, form("astra-dns/log"), _("Log"), 3).leaf = true
	entry({"admin", "services", "astra-dns", "status"}, call("act_status")).leaf = true
	entry({"admin", "services", "astra-dns", "check"}, call("check_update")).leaf = true
	entry({"admin", "services", "astra-dns", "doupdate"}, call("do_update")).leaf = true
	entry({"admin", "services", "astra-dns", "getlog"}, call("get_log")).leaf = true
	entry({"admin", "services", "astra-dns", "dodellog"}, call("do_dellog")).leaf = true
	entry({"admin", "services", "astra-dns", "reloadconfig"}, call("reload_config")).leaf = true
	entry({"admin", "services", "astra-dns", "gettemplateconfig"}, call("get_template_config")).leaf = true
end

local function get_option(name, default)
	return uci:get("astra-dns", "main", name) or default
end

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function get_template_config()
	local template_file = "/usr/share/astra-dns/astra-dns_template.yaml"
	http.prepare_content("text/plain; charset=utf-8")

	if fs.access(template_file) then
		http.write(fs.readfile(template_file) or "")
	else
		http.write("")
	end
end

function reload_config()
	fs.remove(tmp_config)
	http.prepare_content("application/json")
	http.write("{}")
end

function act_status()
	local binpath = get_option("binpath", "/usr/bin/astra-dns")
	local configpath = get_option("configpath", "/etc/astra-dns/named.yaml")
	local version = ""
	if fs.access(binpath) then
		version = sys.exec(shell_quote(binpath) .. " --version 2>/dev/null"):gsub("%s+$", "")
	end

	http.prepare_content("application/json")
	http.write_json({
		running = sys.call("pgrep -f " .. shell_quote(binpath) .. " >/dev/null") == 0,
		redirect = (fs.readfile(redirect_state) == "1"),
		has_bin = fs.access(binpath),
		has_config = fs.access(configpath),
		version = version
	})
end

function do_update()
	local force = http.formvalue("force") == "1"
	local script = "/usr/share/astra-dns/update_core.sh"

	if sys.call("pgrep -f " .. shell_quote(script) .. " >/dev/null") == 0 then
		if force then
			sys.exec("kill $(pgrep -f " .. shell_quote(script) .. ") >/dev/null 2>&1")
		else
			http.prepare_content("application/json")
			http.write("{}")
			return
		end
	end

	local arg = force and " force" or ""
	sys.exec("sh " .. shell_quote(script) .. arg .. " >" .. shell_quote(tmp_update_log) .. " 2>&1 &")
	http.prepare_content("application/json")
	http.write("{}")
end

function get_log()
	http.prepare_content("application/json")
	local logfile = get_option("logfile", "/tmp/astra-dns.log")
	if logfile == "" or not fs.access(logfile) then
		http.write_json({ pos = 0, content = "" })
		return
	end

	local pos = tonumber(http.formvalue("pos")) or 0
	local f = io.open(logfile, "r")
	local content = ""
	local newpos = pos
	if f then
		f:seek("set", pos)
		content = f:read(1048576) or ""
		newpos = f:seek()
		f:close()
	end

	http.write_json({ pos = newpos, content = content })
end

function do_dellog()
	local logfile = get_option("logfile", "/tmp/astra-dns.log")
	if logfile ~= "" then
		fs.writefile(logfile, "")
	end
	http.prepare_content("application/json")
	http.write("{}")
end

function check_update()
	local pos = tonumber(http.formvalue("pos")) or 0
	local content = ""
	local newpos = pos

	if fs.access(tmp_update_log) then
		local f = io.open(tmp_update_log, "r")
		if f then
			f:seek("set", pos)
			content = f:read(1048576) or ""
			newpos = f:seek()
			f:close()
		end
	end

	local running = sys.call("pgrep -f /usr/share/astra-dns/update_core.sh >/dev/null") == 0
	local status = "succeeded"
	if running then
		status = "running"
	elseif fs.access("/var/run/astra-dns-update-error") then
		status = "failed"
	end

	http.prepare_content("application/json")
	http.write_json({ pos = newpos, content = content, status = status })
end
