# LuCI App Astra DNS

Minimal LuCI integration for Astra DNS on OpenWrt.

- Core repo: `https://github.com/astra-sec/astra-dns`
- Plugin repo: `https://github.com/astra-sec/luci-app-astra-dns`

Current scope:

- install plugin scaffolding and default config
- service start / stop / restart with `procd`
- core install / update from release URL
- YAML editor with config validation
- runtime status page
- log viewer
- optional port 53 redirect to Astra DNS

This package intentionally keeps the first version small and YAML-centric.
