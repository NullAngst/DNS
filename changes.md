# Changes

2026.11.09 - Portainer support

* Added portainer.yml to unbound/ and pdns-recursor/, the same stacks with absolute paths to /opt/DNS
* README: Portainer setup steps, a section on changing configs, and how git pull interacts with Portainer's copy of a stack
* maintenance.md: Portainer and terminal steps side by side, plus a check for drift between compose.yml and portainer.yml

Reasons for changes: Portainer CE stacks can't use relative bind mounts, so the compose.yml files couldn't be pasted into Portainer as-is.

2026.11.09 - Initial release

* Unbound compose stack (alpinelinux/unbound) on 127.0.0.1:5335 and 172.30.53.4 on dns-net
* PowerDNS Recursor compose stack (powerdns/pdns-recursor-54) on 127.0.0.1:5354 and 172.30.53.5 on dns-net
* unbound.conf with DNSSEC via Alpine's root trust anchor, QNAME minimisation, serve-expired, prefetch and rebinding protection
* recursor.yml in YAML format with the same settings, plus rebind.lua for rebinding protection
* Shared external dns-net network so Pi-hole, AdGuard Home and other containers can reach both resolvers
* Both resolvers published on the host's 127.0.0.1 only

Reasons for changes: Two independent recursive resolvers in separate stacks, so either one can be run, updated or broken without touching the other.
