local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"

local m, s, o
local configpath = uci:get("astra-dns", "main", "configpath") or "/etc/astra-dns/named.yaml"
local binpath = uci:get("astra-dns", "main", "binpath") or "/usr/bin/astra-dns"
local tmp_config = "/tmp/astra-dns-tmp.yaml"
local validate_log = "/tmp/astra-dns-validate.log"

m = Map("astra-dns")
s = m:section(TypedSection, "main")
s.anonymous = true
s.addremove = false

o = s:option(TextValue, "escconf")
o.rows = 66
o.wrap = "off"
o.rmempty = true
o.cfgvalue = function()
	return fs.readfile(tmp_config)
		or fs.readfile(configpath)
		or fs.readfile("/usr/share/astra-dns/astra-dns_template.yaml")
		or ""
end
o.validate = function(self, value)
	m.message = translate("Configuration validation passed")
	fs.writefile(tmp_config, value:gsub("\r\n", "\n"))
	if fs.access(binpath) then
		sys.call(binpath .. " --validate -c " .. tmp_config .. " >" .. validate_log .. " 2>&1")
		local result = fs.readfile(validate_log) or ""
		if not result:find("Error:", 1, true) then
			return value
		end
		m.message = translate("Configuration validation failed") .. " " .. result
		return nil
	end
	m.message = translate("Core not found, skip validation")
	return value
end
o.write = function()
	fs.move(tmp_config, configpath)
end
o.remove = function()
	fs.writefile(configpath, "")
end

o = s:option(DummyValue, "")
o.anonymous = true
o.template = "astra-dns/yamleditor"
if not fs.access(binpath) then
	o.description = translate("WARNING: No executable found, config will not be tested")
end

if fs.access(tmp_config) then
	local c = fs.readfile(validate_log) or ""
	if c ~= "" and c:find("Error:", 1, true) then
		m.message = translate("Configuration validation failed") .. " " .. c
	end
end

return m

