'use strict';

'require rpc';
'require ui';
'require view';

const callGetConfig = rpc.declare({
	object: 'luci.astra-dns',
	method: 'get_manual_config'
});

const callGetTemplate = rpc.declare({
	object: 'luci.astra-dns',
	method: 'get_template_config'
});

const callSaveConfig = rpc.declare({
	object: 'luci.astra-dns',
	method: 'save_config',
	params: [ 'content' ]
});

const callReloadConfig = rpc.declare({
	object: 'luci.astra-dns',
	method: 'reload_config'
});

let editor;

function resetScroll() {
	document.body.scrollTop = document.documentElement.scrollTop = 0;
}

return view.extend({
	load: function() {
		return L.resolveDefault(callGetConfig(), { content: '', pending: false });
	},

	render: function(data) {
		editor = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;font-family:monospace',
			'rows': 32,
			'wrap': 'off',
			'spellcheck': 'false'
		}, [ data.content || '' ]);

		const reloadButton = E('button', {
			'class': 'cbi-button',
			'style': data.pending ? '' : 'display:none',
			'click': function(ev) {
				ev.preventDefault();
				return L.resolveDefault(callReloadConfig(), {}).then(function() {
					return callGetConfig();
				}).then(function(config) {
					editor.value = config.content || '';
					reloadButton.style.display = config.pending ? '' : 'none';
				});
			}
		}, [ _('Reload config') ]);

		const templateButton = E('button', {
			'class': 'cbi-button',
			'click': function(ev) {
				ev.preventDefault();
				return L.resolveDefault(callGetTemplate(), { content: '' }).then(function(template) {
					editor.value = template.content || '';
				});
			}
		}, [ _('Use template') ]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', _('Manual Config')),
			E('div', { 'class': 'cbi-section' }, [
				editor,
				E('div', { 'class': 'cbi-page-actions' }, [
					reloadButton,
					' ',
					templateButton
				])
			])
		]);
	},

	handleSave: function() {
		return callSaveConfig(editor.value || '').then(function(result) {
			resetScroll();
			if (!result.success) {
				throw new Error(result.log || _('Configuration validation failed'));
			}

			ui.addNotification(null, E('p', _('Configuration saved, Astra DNS reload scheduled')), 'info');
		}).catch(function(err) {
			resetScroll();
			ui.addNotification(null, E('p', _('Unable to save configuration: %s').format(err.message || err)), 'error');
		});
	},

	handleSaveApply: null,
	handleReset: null
});
