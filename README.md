# DNS

Two recursive DNS resolvers in Docker, Unbound and PowerDNS Recursor, for anyone running Pi-hole, AdGuard Home, or a home server that wants to resolve straight from the root servers instead of trusting Google or Cloudflare.

Each one is its own stack, so you can run either or both. Run both and point your filter at both, and DNS keeps working when one goes down. They're different codebases, so a bug in one doesn't take out the other.

| Resolver | Folder | On the host | On dns-net |
| --- | --- | --- | --- |
| Unbound | `unbound/` | 127.0.0.1:5335 | 172.30.53.4:5335 |
| PowerDNS Recursor | `pdns-recursor/` | 127.0.0.1:5354 | 172.30.53.5:5354 |

Both are published on the host's 127.0.0.1 only, so nothing else on your network can use them. Other containers reach them over a shared Docker network called `dns-net`.

## What's in each folder

- `compose.yml` for running it with `docker compose` from the terminal. Uses relative paths, so it works wherever you clone the repo.
- `portainer.yml` for running it as a Portainer stack. Same thing with absolute paths to /opt/DNS, since Portainer CE stacks can't use relative paths.
- The config: `unbound.conf` for Unbound, `recursor.yml` and `rebind.lua` for the Recursor.

Use one or the other for each resolver, not both. They create the same container name, so the second one fails.

## What they do

Both are set up the same way:

- DNSSEC validation
- QNAME minimisation, so each upstream server only sees the part of the name it needs
- Cache with a 60 second minimum and 4 hour maximum TTL
- Serve expired records for up to an hour if a fresh lookup fails
- Refresh popular records before they expire
- Rebinding protection: private and loopback addresses get stripped from public answers
- Version and identity hidden

## Prerequisites

- Docker, plus either the compose plugin or Portainer
- git, or download the repo as a zip from GitHub
- Nothing else on the host using ports 5335 or 5354

## Setup

Steps 1 to 3 happen in the terminal either way.

1. Clone the repo: `git clone https://github.com/NullAngst/DNS.git /opt/DNS`. I use /opt/DNS, since that's where portainer.yml expects it. If you put it somewhere else, change the paths in both portainer.yml files to match.
2. Create the shared network once: `docker network create --driver bridge --subnet 172.30.53.0/24 --gateway 172.30.53.1 dns-net`

   2.5. If that fails with an overlapping-subnet error, something already uses 172.30.53.0/24. Pick another subnet and change it everywhere: the compose.yml and portainer.yml files, the `access-control` line in unbound.conf, and `allow_from` in recursor.yml.

3. Make the configs readable, since neither resolver runs as root inside its container: `chmod 644 /opt/DNS/unbound/* /opt/DNS/pdns-recursor/*`

### With Portainer

4. In Portainer, go to Stacks, then Add stack. Name it `unbound`, pick Web editor, and paste the contents of `unbound/portainer.yml`.
5. Click Deploy the stack.
6. Add another stack named `pdns-recursor`, Web editor, and paste the contents of `pdns-recursor/portainer.yml`.
7. Click Deploy the stack.

Don't use Portainer's Repository option for these. It clones the repo into Portainer's own data folder, and the config mounts end up pointing at paths that don't exist on the host.

### With docker compose

4. Start Unbound: `cd /opt/DNS/unbound && docker compose up -d`
5. Start the Recursor: `cd /opt/DNS/pdns-recursor && docker compose up -d`

## Testing

From the host:

- `dig @127.0.0.1 -p 5335 example.com` should answer with the `ad` flag set. That's Unbound, and `ad` means DNSSEC validated.
- `dig @127.0.0.1 -p 5354 example.com` should do the same. That's the Recursor.
- `dig @127.0.0.1 -p 5335 dnssec-failed.org` and `dig @127.0.0.1 -p 5354 dnssec-failed.org` should both come back SERVFAIL, since that domain's DNSSEC is broken on purpose. IF EITHER ONE ANSWERS, DNSSEC IS OFF ON THAT RESOLVER.
- `docker exec pdns-recursor rec_control get-tas` should list key tag 38696, the current root key.
- Check the logs for errors, with `docker logs unbound` and `docker logs pdns-recursor`, or in Portainer under Containers, then the container, then Logs. The Recursor log should show it listening on port 5354 and loading /etc/powerdns/rebind.lua.

If Unbound answers dnssec-failed.org, the trust anchor file probably isn't where unbound.conf expects. Find it with `docker exec unbound find / -name '*.key' -path '*dnssec*'`, then fix the `trust-anchor-file` line to match.

## Using them from Pi-hole or AdGuard Home

If Pi-hole or AdGuard Home runs on the host itself, use `127.0.0.1#5335` and `127.0.0.1#5354` in Pi-hole, or `127.0.0.1:5335` and `127.0.0.1:5354` in AdGuard Home.

If they run in Docker, join them to `dns-net` instead, since 127.0.0.1 inside a container is the container itself. Add this to their compose file or Portainer stack, with a free IP in the subnet:

```yaml
    networks:
      dns-net:
        ipv4_address: 172.30.53.2

networks:
  dns-net:
    external: true
    name: dns-net
```

Then set the upstreams to the dns-net addresses:

- Pi-hole: `FTLCONF_dns_upstreams: '172.30.53.4#5335;172.30.53.5#5354'` in its environment, or Settings, DNS in the web UI.
- AdGuard Home: `172.30.53.4:5335` and `172.30.53.5:5354` on separate lines under Settings, DNS settings, Upstream DNS servers. I use load balancing so both resolvers take traffic, since a backup that never gets queries can sit broken for months without you knowing.

## Changing a config

Edit the file in /opt/DNS, then restart that container: `docker restart unbound` or `docker restart pdns-recursor`, or the Restart button in Portainer under Containers. The configs are mounted, so a restart picks up the change. No redeploy needed.

For Unbound, check the config first: `docker exec unbound unbound-checkconf`. A typo stops Unbound from starting.

## Notes

- Neither resolver uses IPv6 for outgoing queries, since Docker bridges don't have IPv6 by default. If you've enabled IPv6 in Docker, set `do-ip6: yes` in unbound.conf and add `- "::"` under `source_address` in recursor.yml.
- `so-rcvbuf: 1m` in unbound.conf only works if the host allows it. If Unbound logs that it wasn't granted, put `net.core.rmem_max = 1048576` in a file under /etc/sysctl.d/ and run `sysctl --system`.
- The rebinding protection blocks loopback too. Domains that point at 127.0.0.1 on purpose, like some local development setups, won't resolve.
- `git pull` in /opt/DNS updates the configs. Restart the containers afterward. If the update changed a portainer.yml, paste the new version into that stack's editor in Portainer too, since Portainer keeps its own copy.

Now Unbound and PowerDNS Recursor are both resolving from the root servers with DNSSEC, reachable from the host and anything on dns-net, and closed to everything else. Tinker with the cache sizes and thread counts as you see fit.
