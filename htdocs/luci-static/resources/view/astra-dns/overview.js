'use strict';

'require dom';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const callStatus = rpc.declare({
	object: 'luci.astra-dns',
	method: 'status'
});

function statusText(status) {
	const running = status.running
		? E('span', { 'style': 'color:green' }, _('Astra DNS RUNNING'))
		: E('span', { 'style': 'color:red' }, _('Astra DNS NOT RUNNING'));

	const redirect = status.redirect
		? E('span', { 'style': 'color:green' }, [ ' (', _('Redirected'), ')' ])
		: E('span', { 'style': 'color:red' }, [ ' (', _('Not redirected'), ')' ]);

	return E('em', [ E('strong', [ running, redirect ]) ]);
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {})
		]);
	},

	render: function(data) {
		const initialStatus = data[0] || {};
		const statusEl = E('p', { 'id': 'astra_dns_status' }, statusText(initialStatus));

		poll.add(function() {
			return L.resolveDefault(callStatus(), {}).then(function(status) {
				dom.content(statusEl, statusText(status));
			});
		}, 3);

		const m = new form.Map('astra-dns', 'Astra DNS',
			_('A lightweight LuCI interface for managing Astra DNS.'));

		const statusSection = E('div', { 'class': 'cbi-section' }, [ statusEl ]);

		let s = m.section(form.NamedSection, 'main', 'main', _('Settings'));
		s.addremove = false;
		s.tab('basic', _('Basic Settings'));
		s.tab('core', _('Core Settings'));

		let o = s.taboption('basic', form.DummyValue, '_core_status', _('Core'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (!initialStatus.has_bin)
				return '<font color="red">' + _('No core') + '</font>';

			if (initialStatus.version)
				return '<font color="green">' + initialStatus.version + '</font>';

			return '<font color="red">' + _('Core error') + '</font>';
		};

		o = s.taboption('basic', form.Flag, 'enabled', _('Enable'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('basic', form.ListValue, 'redirect', _('DNS redirect mode'));
		o.value('none', _('None'));
		o.value('redirect', _('Redirect port 53 to Astra DNS'));
		o.default = 'none';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'configpath', _('Config path'));
		o.default = '/etc/astra-dns/named.yaml';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'logfile', _('Runtime log file path'));
		o.default = '';
		o.placeholder = _('Use system log');
		o.rmempty = true;

		o = s.taboption('core', form.Value, 'binpath', _('Astra DNS executable file path'));
		o.default = '/usr/bin/astra-dns';
		o.rmempty = false;

			o = s.taboption('core', form.Value, 'target', _('Release target'));
			o.default = '';
		o.placeholder = _('Auto detect');
		o.rmempty = true;
		o.description = _('Example: aarch64-unknown-linux-musl');

		o = s.taboption('core', form.TextValue, 'downloadlinks', _('Download links for update'));
		o.rows = 4;
		o.wrap = 'soft';
		o.default = 'https://github.com/astra-sec/astra-dns/releases/latest/download/astra-dns-${Target}.tar.gz';
		o.rmempty = false;
		o.cfgvalue = function(section_id) {
			return uci.get('astra-dns', section_id, 'downloadlinks') || this.default;
		};
		o.write = function(section_id, value) {
			uci.set('astra-dns', section_id, 'downloadlinks', (value || '').replace(/\r\n?/g, '\n'));
		};

		return m.render().then(function(mapEl) {
			return E([ statusSection, mapEl ]);
		});
	}
});
