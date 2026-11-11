# Changes

2026.11.11 - dnsdist stack

* Added dnsdist/ with compose.yml and portainer.yml for powerdns/dnsdist-21, on host networking, starting as root and dropping to pdns after binding port 53
* dnsdist.conf ported from the host install: AdGuard Home on 127.0.0.1:5300 as the backend, open ACL, ANY dropped, TC for TXT, DNSKEY and RRSIG over UDP, 20 qps per IP UDP limit with TC, 100 qps hard limit
* Blocklist and ANY drops moved above the emergency TC rule, so blocked addresses get nothing back even with it on
* Emergency force-TCP rule left commented out
* Blocklist moved to /etc/dnsdist/blocklist/blocked.txt, mounted as a folder. Bad lines in it are now skipped with a warning instead of stopping dnsdist from starting, and inline # comments are allowed.
* update-blocklist.sh: downloads BlissDNS badips.txt, checks every line, refuses an empty list or one that shrank by more than half, swaps the file in atomically and restarts dnsdist only when the list changed
* .gitignore for the generated blocklist
* README: dnsdist section covering what it does, why host networking, prerequisites, setup, cron and testing
* maintenance.md: dnsdist series check, outside port checks, blocklist check, and dnsdist added to the image, memory, config and drift steps

Reasons for changes: dnsdist was running straight on the host while everything else in this repo runs in Docker. Host networking keeps the real client address on every query, which the per-IP rate limits and the blocklist depend on.

2026.11.09 - Backend overhaul

* Unbound's root trust anchor now comes from the host's dns-root-data package, mounted at /etc/unbound/root.key, instead of the copy inside the Alpine image
* Added the root.key mount to both unbound/compose.yml and unbound/portainer.yml
* README: dns-root-data as a prerequisite and setup step, SERVFAIL troubleshooting, and a section on router DNS redirects causing lookup loops
* maintenance.md: checks for the host's root key and for router DNS hijacking

Reasons for changes: Unbound SERVFAILed on every lookup with the image's trust anchor, and worked once pointed at dns-root-data's root.key. The host's package manager keeps that file current through root key changes. A router DNS redirect also caused a lookup loop during setup, so the docs now cover how to spot and fix it.

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
