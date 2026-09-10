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

const callStartUpdate = rpc.declare({
	object: 'luci.astra-dns',
	method: 'start_update',
	params: [ 'force' ]
});

const callCheckUpdate = rpc.declare({
	object: 'luci.astra-dns',
	method: 'check_update',
	params: [ 'pos' ]
});

function statusText(status) {
	const running = status.running
		? E('span', { 'style': 'color:green' }, [ 'Astra DNS ', _('RUNNING') ])
		: E('span', { 'style': 'color:red' }, [ 'Astra DNS ', _('NOT RUNNING') ]);

	const redirect = status.redirect
		? E('span', { 'style': 'color:green' }, [ ' (', _('Redirected'), ')' ])
		: E('span', { 'style': 'color:red' }, [ ' (', _('Not redirected'), ')' ]);

	return E('em', [ E('strong', [ running, redirect ]) ]);
}

function coreStatusHtml(status) {
	if (!status.has_bin)
		return '<font color="red">' + _('No core') + '</font>';

	if (status.version)
		return '<font color="green">' + status.version + '</font>';

	return '<font color="red">' + _('Core error') + '</font>';
}

function renderUpdateWidget(refreshStatus) {
	let logPos = 0;
	let pollTimer = null;
	let reverse = false;
	let updateStarted = false;

	const logView = E('div', { 'style': 'display:none' });

	const logEl = E('textarea', {
		'class': 'cbi-input-textarea',
		'style': 'width:100%;display:block;margin-top:.5em',
		'rows': 5,
		'readonly': 'readonly'
	});

	const startButton = E('button', {
		'class': 'cbi-button cbi-button-apply',
		'click': function(ev) {
			ev.preventDefault();
			startUpdate(false);
		}
	}, [ _('Install / Update core') ]);

	const forceButton = E('button', {
		'class': 'cbi-button cbi-button-reset',
		'style': 'display:none',
		'click': function(ev) {
			ev.preventDefault();
			startUpdate(true);
		}
	}, [ _('Force update') ]);

	const reverseBox = E('input', {
		'type': 'checkbox',
		'click': function() {
			reverse = !reverse;
			logEl.value = logEl.value.split('\n').reverse().join('\n');
		}
	});

	function setRunning(running) {
		startButton.disabled = running;
		startButton.textContent = running ? _('Updating...') : _('Install / Update core');
		if (running)
			forceButton.style.display = 'inline';
	}

	function appendLog(content) {
		if (!content)
			return;

		if (reverse)
			logEl.value = content.split('\n').reverse().join('\n') + logEl.value;
		else
			logEl.value += content;
	}

	function pollUpdate(showSuccess) {
		return L.resolveDefault(callCheckUpdate(logPos), {}).then(function(data) {
			if (showSuccess || data.status == 'running' || data.status == 'failed')
				appendLog(data.content || '');
			if (data.pos != null)
				logPos = parseInt(data.pos, 10) || logPos;

			if (data.status == 'running') {
				logView.style.display = '';
				setRunning(true);
				pollTimer = window.setTimeout(function() { pollUpdate(showSuccess); }, 3000);
			}
			else {
				setRunning(false);
				if (data.status == 'succeeded' && showSuccess) {
					logView.style.display = '';
					startButton.disabled = true;
					startButton.textContent = _('Updated');
				}
				else if (data.status == 'failed') {
					startButton.disabled = false;
					startButton.textContent = _('Install / Update core');
					logView.style.display = '';
				}
				else if (!showSuccess && !updateStarted) {
					logView.style.display = 'none';
				}

				if (showSuccess && data.status != 'running')
					refreshStatus();
			}
		});
	}

	function startUpdate(force) {
		if (pollTimer)
			window.clearTimeout(pollTimer);

		logPos = 0;
		logEl.value = '';
		updateStarted = true;
		logView.style.display = '';
		setRunning(true);

		return L.resolveDefault(callStartUpdate(!!force), {})
			.then(function() { return pollUpdate(true); })
			.catch(function(err) {
				setRunning(false);
				ui.addNotification(null, E('p', _('Unable to start update: %s').format(err.message || err)), 'error');
			});
	}

	dom.append(logView, [
		E('label', [
			reverseBox,
			' ',
			_('Reverse')
		]),
		logEl
	]);

	pollUpdate(false);

	return E('div', {}, [
		E('p', { 'style': 'margin-top:0' }, [
			startButton,
			' ',
			forceButton
		]),
		logView
	]);
}

const CBIUpdateValue = form.DummyValue.extend({
	renderWidget: function() {
		this.coreStatusEl.innerHTML = coreStatusHtml(this.initialStatus);

		return E('div', {}, [
			E('div', { 'style': 'margin-bottom:.5em' }, [
				_('Core status:'),
				' ',
				this.coreStatusEl
			]),
			renderUpdateWidget(this.refreshStatus)
		]);
	}
});

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {})
		]);
	},

	render: function(data) {
		const initialStatus = data[0] || {};
		const statusEl = E('p', { 'id': 'astra_dns_status' }, statusText(initialStatus));
		const coreStatusEl = E('span', { 'id': 'astra_dns_core_status' });

		function refreshStatus() {
			return L.resolveDefault(callStatus(), {}).then(function(status) {
				dom.content(statusEl, statusText(status));
				coreStatusEl.innerHTML = coreStatusHtml(status);
			});
		}

		poll.add(function() {
			return refreshStatus();
		}, 3);

		const m = new form.Map('astra-dns', 'Astra DNS',
			_('A lightweight LuCI interface for managing Astra DNS.'));

		const statusSection = m.section(form.NamedSection, 'main', 'main');
		statusSection.render = function() {
			return E('div', { 'class': 'cbi-section' }, [ statusEl ]);
		};

		let s = m.section(form.NamedSection, 'main', 'main');
		s.addremove = false;
		s.tab('basic', _('Basic Settings'));
		s.tab('core', _('Core Settings'));

		let o = s.taboption('basic', form.Flag, 'enabled', _('Enable'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('basic', CBIUpdateValue, '_core_update', _('Core'));
		o.initialStatus = initialStatus;
		o.coreStatusEl = coreStatusEl;
		o.refreshStatus = refreshStatus;
		o.cfgvalue = function() {
			return null;
		};

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

		return m.render();
	}
});
