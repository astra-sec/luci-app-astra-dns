local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

local f, t
f = SimpleForm("logview")
f.reset = false
f.submit = false
t = f:field(TextValue, "conf")
t.rmempty = true
t.rows = 20
t.template = "astra-dns/log"
t.readonly = "readonly"
local logfile = uci:get("astra-dns", "main", "logfile") or ""
t.timereplace = false
t.pollcheck = logfile ~= ""

return f

