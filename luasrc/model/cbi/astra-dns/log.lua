local f, t
f = SimpleForm("logview")
f.reset = false
f.submit = false
t = f:field(TextValue, "conf")
t.rmempty = true
t.rows = 20
t.template = "astra-dns/log"
t.readonly = "readonly"
t.timereplace = false

return f
