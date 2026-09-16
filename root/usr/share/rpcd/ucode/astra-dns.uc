#!/usr/bin/env ucode
'use strict';

import { access, dirname, popen, readfile, unlink, writefile } from 'fs';
import { cursor } from 'uci';

const CONFIG = 'astra-dns';
const TMP_CONFIG = '/tmp/astra-dns-tmp.yaml';
const VALIDATE_LOG = '/tmp/astra-dns-validate.log';
const UPDATE_LOG = '/tmp/astra-dns_update.log';
const UPDATE_ERROR = '/var/run/astra-dns-update-error';
const UPDATE_STATE = '/var/run/astra-dns-update-state';
const REDIRECT_STATE = '/var/run/astra_dns_redirect';
const TEMPLATE_CONFIG = '/usr/share/astra-dns/astra-dns_template.yaml';
const UPDATE_SCRIPT = '/usr/share/astra-dns/update_core.sh';

function uci_get(option, fallback) {
	const uci = cursor();
	const value = uci.get(CONFIG, 'main', option);
	uci.unload(CONFIG);
	return value ?? fallback;
}

function shellquote(value) {
	if (value == null)
		value = '';

	return "'" + replace(value, "'", "'\\''") + "'";
}

function run_capture(command) {
	const fp = popen(command, 'r');
	if (!fp)
		return '';

	const output = fp.read('all') || '';
	fp.close();
	return output;
}

function is_update_running() {
	return system(`pgrep -f ${shellquote(UPDATE_SCRIPT)} >/dev/null 2>&1`) == 0;
}

function astra_running(binpath, configpath) {
	return system('/etc/init.d/astra-dns isrunning >/dev/null 2>&1') == 0;
}

function read_log_chunk(log, pos) {
	pos = int(pos || 0);
	if (pos > 0 && length(log) >= pos)
		return { pos: length(log), content: substr(log, pos) };

	return { pos: length(log), content: log };
}

function read_system_log() {
	return run_capture("logread -e 'astra-dns' 2>/dev/null");
}

function read_file_chunk(path, pos) {
	const fp = popen(`dd if=${shellquote(path)} bs=1 skip=${int(pos || 0)} count=1048576 2>/dev/null`, 'r');
	if (!fp)
		return { pos: 0, content: '' };

	const content = fp.read('all') || '';
	fp.close();
	return { pos: int(pos || 0) + length(content), content };
}

function normalize_newlines(value) {
	return replace(value ?? '', /\r\n?/g, '\n');
}

function validate_config_content(content) {
	const binpath = uci_get('binpath', '/usr/bin/astra-dns');

	writefile(TMP_CONFIG, normalize_newlines(content));

	if (!access(binpath, 'x'))
		return { success: true, skipped: true, log: 'Core not found, skip validation' };

	const code = system(`${shellquote(binpath)} --validate -c ${shellquote(TMP_CONFIG)} >${shellquote(VALIDATE_LOG)} 2>&1`, 30000);
	const log = readfile(VALIDATE_LOG) || '';

	return { success: code == 0, skipped: false, log };
}

const methods = {
	status: {
		call: function() {
			const binpath = uci_get('binpath', '/usr/bin/astra-dns');
			const configpath = uci_get('configpath', '/etc/astra-dns/named.yaml');
			const version = access(binpath, 'x')
				? trim(run_capture(`${shellquote(binpath)} --version 2>/dev/null`))
				: '';

			return {
				running: astra_running(binpath, configpath),
				redirect: trim(readfile(REDIRECT_STATE) || '') == '1',
				has_bin: !!access(binpath, 'x'),
				has_config: !!access(configpath, 'f'),
				version
			};
		}
	},

	get_template_config: {
		call: function() {
			return { content: readfile(TEMPLATE_CONFIG) || '' };
		}
	},

	get_manual_config: {
		call: function() {
			const configpath = uci_get('configpath', '/etc/astra-dns/named.yaml');
			const pending = !!access(TMP_CONFIG, 'f');
			const content = readfile(pending ? TMP_CONFIG : configpath)
				?? readfile(TEMPLATE_CONFIG)
				?? '';

			return { content, pending };
		}
	},

	reload_config: {
		call: function() {
			unlink(TMP_CONFIG);
			return {};
		}
	},

	validate_config: {
		args: { content: '' },
		call: function(req) {
			return validate_config_content(req.args.content);
		}
	},

	save_config: {
		args: { content: '' },
		call: function(req) {
			const result = validate_config_content(req.args.content);
			if (!result.success)
				return result;

			const configpath = uci_get('configpath', '/etc/astra-dns/named.yaml');
			const content = normalize_newlines(req.args.content);
			const existing = readfile(configpath);
			let changed = false;

			if (existing != content) {
				system(`mkdir -p ${shellquote(dirname(configpath))}`);
				if (!writefile(configpath, content))
					return { success: false, log: `Failed to write ${configpath}` };
				changed = true;
			}

			unlink(TMP_CONFIG);
			system('/etc/init.d/astra-dns reload >/dev/null 2>&1 &');

			result.changed = changed;
			return result;
		}
	},

	start_update: {
		args: { force: false },
		call: function(req) {
			if (is_update_running()) {
				if (req.args.force) {
					system(`kill $(pgrep -f ${shellquote(UPDATE_SCRIPT)}) >/dev/null 2>&1`);
					system(`i=0; while pgrep -f ${shellquote(UPDATE_SCRIPT)} >/dev/null 2>&1 && [ "$i" -lt 10 ]; do i=$((i + 1)); sleep 1; done`);
				}
				else {
					return { running: true };
				}
			}

			unlink(UPDATE_ERROR);
			writefile(UPDATE_STATE, 'running\n');
			writefile(UPDATE_LOG, '');

			const arg = req.args.force ? ' force' : '';
			system(`sh ${shellquote(UPDATE_SCRIPT)}${arg} >${shellquote(UPDATE_LOG)} 2>&1 &`);
			return { running: true };
		}
	},

	check_update: {
		args: { pos: 0 },
		call: function(req) {
			let result = access(UPDATE_LOG, 'f')
				? read_file_chunk(UPDATE_LOG, req.args.pos)
				: { pos: 0, content: '' };
			const state = trim(readfile(UPDATE_STATE) || '');

			if (is_update_running())
				result.status = 'running';
			else if (state == 'succeeded' || state == 'failed')
				result.status = state;
			else if (access(UPDATE_ERROR, 'f'))
				result.status = 'failed';
			else
				result.status = 'idle';

			return result;
		}
	},

	get_log: {
		args: { pos: 0 },
		call: function(req) {
			const logfile = uci_get('logfile', '');

			if (logfile == '')
				return read_log_chunk(read_system_log(), req.args.pos);

			if (!access(logfile, 'f'))
				return { pos: 0, content: '' };

			return read_file_chunk(logfile, req.args.pos);
		}
	},

	clear_log: {
		call: function() {
			const logfile = uci_get('logfile', '');

			if (logfile != '') {
				writefile(logfile, '');
				return { pos: 0 };
			}

			return { pos: length(read_system_log()) };
		}
	},

	service_action: {
		args: { action: '' },
		call: function(req) {
			const action = req.args.action;
			const valid_actions = [ 'start', 'stop', 'restart', 'reload' ];

			if (index(valid_actions, action) < 0)
				return { success: false, code: 1, error: 'Invalid action' };

			const code = system(`env -i /etc/init.d/astra-dns ${action} >/dev/null`);
			return { success: code == 0, code };
		}
	}
};

return { 'luci.astra-dns': methods };
