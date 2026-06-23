'use strict';

'require rpc';
'require ui';
'require view';

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

return view.extend({
	render: function() {
		let logPos = 0;
		let pollTimer = null;
		let reverse = false;

		const logEl = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;display:block',
			'rows': 8,
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
				appendLog(data.content || '');
				if (data.pos != null)
					logPos = parseInt(data.pos, 10) || logPos;

				if (data.status == 'running') {
					setRunning(true);
					pollTimer = window.setTimeout(function() { pollUpdate(showSuccess); }, 3000);
				}
				else {
					setRunning(false);
					forceButton.style.display = data.status == 'failed' ? '' : 'none';
					if (showSuccess && data.status == 'succeeded')
						startButton.textContent = _('Updated');
				}
			});
		}

		function startUpdate(force) {
			if (pollTimer)
				window.clearTimeout(pollTimer);

			logPos = 0;
			logEl.value = '';
			forceButton.style.display = 'none';
			setRunning(true);

			return L.resolveDefault(callStartUpdate(!!force), {})
				.then(function() { return pollUpdate(true); })
				.catch(function(err) {
					setRunning(false);
					ui.addNotification(null, E('p', _('Unable to start update: %s').format(err.message || err)), 'error');
				});
		}

		pollUpdate(false);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('Astra DNS Core Update')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', [ startButton, ' ', forceButton ]),
				E('label', [ reverseBox, ' ', _('Reverse') ]),
				logEl
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
