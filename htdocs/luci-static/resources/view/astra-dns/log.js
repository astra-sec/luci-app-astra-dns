'use strict';

'require rpc';
'require view';

const callGetLog = rpc.declare({
	object: 'luci.astra-dns',
	method: 'get_log',
	params: [ 'pos' ]
});

const callClearLog = rpc.declare({
	object: 'luci.astra-dns',
	method: 'clear_log'
});

return view.extend({
	render: function() {
		let logPos = 0;
		let reverse = true;

		const logEl = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;display:inline',
			'rows': 32,
			'cols': 60,
			'readonly': 'readonly'
		});

		function appendLog(content) {
			if (!content)
				return;

			if (reverse)
				logEl.value = content.split('\n').reverse().join('\n') + logEl.value;
			else
				logEl.value += content;
		}

		function pollLog() {
			return L.resolveDefault(callGetLog(logPos), {}).then(function(data) {
				appendLog(data.content || '');
				if (data.pos != null)
					logPos = parseInt(data.pos, 10) || logPos;

					window.setTimeout(pollLog, 3000);
			});
		}

		function downloadLog() {
			const dt = new Date();
			const timestamp = (dt.getMonth() + 1) + '-' + dt.getDate() + '-' + dt.getHours() + '_' + dt.getMinutes();
			const link = document.createElement('a');
			const blob = new Blob([ logEl.value ]);

			link.download = 'astra-dns-' + timestamp + '.log';
			link.href = URL.createObjectURL(blob);
			link.click();
			URL.revokeObjectURL(blob);
		}

		pollLog();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('Log')),
			E('div', { 'class': 'cbi-section' }, [
				E('label', [
					E('input', {
						'type': 'checkbox',
						'checked': 'checked',
						'click': function() {
							reverse = !reverse;
							logEl.value = logEl.value.split('\n').reverse().join('\n');
						}
					}),
					' ',
					_('Reverse')
				]),
				E('br'),
				logEl,
				E('div', { 'class': 'cbi-page-actions' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': function(ev) {
							ev.preventDefault();
							return L.resolveDefault(callClearLog(), { pos: 0 }).then(function(data) {
								logEl.value = '';
								logPos = parseInt(data.pos, 10) || 0;
							});
						}
					}, [ _('Clear log') ]),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': function(ev) {
							ev.preventDefault();
							downloadLog();
						}
					}, [ _('Download log') ])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
