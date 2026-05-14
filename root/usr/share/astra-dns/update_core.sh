#!/bin/sh

set -eu

CONFIG=astra-dns
ERROR_FLAG=/var/run/astra-dns-update-error

log() {
	echo "$@"
}

install_binary() {
	local src="$1"
	local dest="$2"
	cp "$src" "$dest"
	chmod 0755 "$dest"
}

config_get_option() {
	local option="$1"
	local default="$2"
	uci -q get ${CONFIG}.main.${option} 2>/dev/null || printf '%s' "$default"
}

detect_target() {
	local override
	override="$(config_get_option target "")"
	if [ -n "$override" ]; then
		printf '%s' "$override"
		return
	fi

	case "$(uname -m)" in
		x86_64) printf '%s' "x86_64-unknown-linux-musl" ;;
		aarch64|arm64) printf '%s' "aarch64-unknown-linux-musl" ;;
		armv7l|armv7) printf '%s' "armv7-unknown-linux-musleabihf" ;;
		*) return 1 ;;
	esac
}

download_file() {
	local url="$1"
	local dest="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fL "$url" -o "$dest"
	else
		wget -O "$dest" "$url"
	fi
}

rm -f "$ERROR_FLAG"

BINPATH="$(config_get_option binpath /usr/bin/astra-dns)"
WORKDIR="$(config_get_option workdir /var/lib/astra-dns)"
DOWNLOADLINKS="$(config_get_option downloadlinks 'https://github.com/astra-sec/astra-dns/releases/latest/download/astra-dns-${Target}.tar.gz')"
TARGET="$(detect_target)" || {
	log "Unsupported architecture, please set release target manually."
	touch "$ERROR_FLAG"
	exit 1
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

mkdir -p "$(dirname "$BINPATH")" "$WORKDIR"

success=0
IFS='
'
for raw_url in $DOWNLOADLINKS; do
	case "$raw_url" in
		''|\#*) continue ;;
	esac
	url="$(printf '%s' "$raw_url" | sed "s|\${Target}|$TARGET|g")"
	archive="$TMPDIR/archive.tar.gz"
	log "Downloading: $url"
	if ! download_file "$url" "$archive"; then
		log "Download failed: $url"
		continue
	fi

	if ! tar -xzf "$archive" -C "$TMPDIR"; then
		log "Extract failed: $url"
		continue
	fi

	if [ ! -f "$TMPDIR/astra-dns" ]; then
		log "astra-dns binary not found in archive"
		continue
	fi

	install_binary "$TMPDIR/astra-dns" "$BINPATH"
	success=1
	break
done
unset IFS

if [ "$success" != "1" ]; then
	log "No download source succeeded."
	touch "$ERROR_FLAG"
	exit 1
fi

log "Installed Astra DNS to $BINPATH"
/etc/init.d/astra-dns restart >/dev/null 2>&1 || true
log "Done"
