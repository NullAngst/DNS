# DNS

Two recursive DNS resolvers in Docker, Unbound and PowerDNS Recursor, for anyone running Pi-hole, AdGuard Home, or a home server that wants to resolve straight from the root servers instead of trusting Google or Cloudflare.

Each one is its own stack, so you can run either or both. Run both and point your filter at both, and DNS keeps working when one goes down. They're different codebases, so a bug in one doesn't take out the other.

| Resolver | Folder | On the host | On dns-net |
| --- | --- | --- | --- |
| Unbound | `unbound/` | 127.0.0.1:5335 | 172.30.53.4:5335 |
| PowerDNS Recursor | `pdns-recursor/` | 127.0.0.1:5354 | 172.30.53.5:5354 |

Both are published on the host's 127.0.0.1 only, so nothing else on your network can use them. Other containers reach them over a shared Docker network called `dns-net`.

There's also an optional third stack, dnsdist, for running AdGuard Home as a public resolver. It sits on port 53 in front of AdGuard Home and handles rate limiting, an IP blocklist and abuse rules for plain DNS. Most people don't need it. See "dnsdist" below.

## What's in each folder

- `compose.yml` for running it with `docker compose` from the terminal. Uses relative paths, so it works wherever you clone the repo.
- `portainer.yml` for running it as a Portainer stack. Same thing with absolute paths to /opt/DNS, since Portainer CE stacks can't use relative paths.
- The config: `unbound.conf` for Unbound, `recursor.yml` and `rebind.lua` for the Recursor, `dnsdist.conf` and `update-blocklist.sh` for dnsdist.

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
- The root DNSSEC key on the host at /usr/share/dns/root.key, for Unbound. On Debian and Ubuntu that's the dns-root-data package.
- Nothing else on the host using ports 5335 or 5354
- If your router forces all DNS through itself, like GL.iNet's DNS override, the host has to be excluded from that. See "Router DNS redirects" below.

## Setup

Steps 1 to 4 happen in the terminal either way.

1. Clone the repo: `git clone https://github.com/NullAngst/DNS.git /opt/DNS`. I use /opt/DNS, since that's where portainer.yml expects it. If you put it somewhere else, change the paths in both portainer.yml files to match.
2. Create the shared network once: `docker network create --driver bridge --subnet 172.30.53.0/24 --gateway 172.30.53.1 dns-net`

   2.5. If that fails with an overlapping-subnet error, something already uses 172.30.53.0/24. Pick another subnet and change it everywhere: the compose.yml and portainer.yml files, the `access-control` line in unbound.conf, and `allow_from` in recursor.yml.

3. Make the configs readable, since neither resolver runs as root inside its container: `chmod 644 /opt/DNS/unbound/* /opt/DNS/pdns-recursor/*`
4. Install the root key for Unbound. I use apt, so in my case `apt install dns-root-data`. It depends on your system, but you need the root key file at /usr/share/dns/root.key, or change that path in Unbound's compose.yml and portainer.yml to wherever your distro puts it. Check it has the current root key: `grep -c 38696 /usr/share/dns/root.key` should print 1.

   WITHOUT THIS FILE, UNBOUND WON'T START. With an outdated one, it starts but every lookup SERVFAILs.

### With Portainer

5. In Portainer, go to Stacks, then Add stack. Name it `unbound`, pick Web editor, and paste the contents of `unbound/portainer.yml`.
6. Click Deploy the stack.
7. Add another stack named `pdns-recursor`, Web editor, and paste the contents of `pdns-recursor/portainer.yml`.
8. Click Deploy the stack.

Don't use Portainer's Repository option for these. It clones the repo into Portainer's own data folder, and the config mounts end up pointing at paths that don't exist on the host.

### With docker compose

5. Start Unbound: `cd /opt/DNS/unbound && docker compose up -d`
6. Start the Recursor: `cd /opt/DNS/pdns-recursor && docker compose up -d`

## Testing

From the host:

- `dig @127.0.0.1 -p 5335 example.com` should answer with the `ad` flag set. That's Unbound, and `ad` means DNSSEC validated.
- `dig @127.0.0.1 -p 5354 example.com` should do the same. That's the Recursor.
- `dig @127.0.0.1 -p 5335 dnssec-failed.org` and `dig @127.0.0.1 -p 5354 dnssec-failed.org` should both come back SERVFAIL, since that domain's DNSSEC is broken on purpose. IF EITHER ONE ANSWERS, DNSSEC IS OFF ON THAT RESOLVER.
- `docker exec pdns-recursor rec_control get-tas` should list key tag 38696, the current root key.
- Check the logs for errors, with `docker logs unbound` and `docker logs pdns-recursor`, or in Portainer under Containers, then the container, then Logs. The Recursor log should show it listening on port 5354 and loading /etc/powerdns/rebind.lua.

If either resolver SERVFAILs on everything:

- Run the same `dig` with `+cd` on the end, which turns validation off. If it answers with `+cd` and fails without, that resolver's root key is stale. For Unbound, check `grep -c 38696 /usr/share/dns/root.key` on the host and update dns-root-data. For the Recursor, update the image.
- If it fails both ways, the resolver can't reach the root servers. From the host, `dig @198.41.0.4 . NS +norec` should show `aa` in the flags and list 13 root servers. If it shows `ra` and no answers, your router is hijacking port 53. See "Router DNS redirects" below.
- After fixing either one, restart the container. Both resolvers remember servers they couldn't reach and stop trying them for a while.

## Router DNS redirects

Some routers force every device's DNS through themselves, GL.iNet's DNS override for one. That catches the resolvers' own queries to the root servers and hands them to whatever DNS the router uses. If that's your Pi-hole or AdGuard Home, which forwards back to these resolvers, you've got a loop. The signs are SERVFAIL on everything, and a flood of lookups for `.` in Pi-hole or AdGuard Home's log with your router as the client.

The fix is to exclude the host from the redirect on the router. For OpenWrt and GL.iNet, [exclude-script.sh](https://github.com/MZGSZM/scripts/tree/main/linux) does it. Then restart both containers.

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

## dnsdist

This stack is for a public resolver: AdGuard Home answering the internet, with dnsdist taking plain DNS on port 53 in front of it. AdGuard Home keeps DoH, DoT and DoQ itself, since abuse like TXT reflection floods hits plain DNS and nothing else. If your AdGuard Home or Pi-hole only serves your own network, skip this stack.

What `dnsdist.conf` does, in order, first match wins:

- Drops anything from an address in `blocklist/blocked.txt`
- Drops ANY queries
- Answers TXT, DNSKEY and RRSIG over UDP with TC, so real clients retry over TCP and spoofed ones get nothing big back
- Answers TC to any IP over 20 queries a second on UDP, counted per /32 for IPv4 and per /64 for IPv6. TC instead of a drop, so a lot of users behind one NAT still resolve.
- Drops any IP over 100 queries a second
- Sends the rest to AdGuard Home on 127.0.0.1:5300

There's also an emergency line, commented out, that forces TC on every UDP query. Uncomment it during a flood you can't otherwise shake, and comment it back out after.

### Why it's not on dns-net

The other two stacks use dns-net. This one uses host networking, and that's on purpose. Why? Because dnsdist's rules are all per client address, so it has to see the real one. With a published port on a bridge network, Docker hands IPv6 connections to docker-proxy, which forwards them over IPv4 unless you've set up IPv6 on that network. Every IPv6 client then shows up as the bridge gateway, 172.30.53.1. They all share one 20 qps bucket, so they all get TC, and IPv6 entries in the blocklist never match anything. Host networking skips docker-proxy and the NAT entirely.

The catch is that the image runs as an unprivileged user, and on the host network it can't bind port 53. So the container starts as root and dnsdist drops to the image's pdns user right after it opens its sockets, with `--uid pdns --gid pdns`.

### Prerequisites

- AdGuard Home's plain DNS listener moved off 53, to 5300. I run AdGuard Home on the host, so in my case that's `127.0.0.1:5300`. If yours is in Docker on dns-net, change the `newServer` line in dnsdist.conf to its dns-net address, like `172.30.53.2:5300`, since 127.0.0.1 here is the host.
- Port 5300 closed from outside, in your firewall or by having AdGuard Home listen on 127.0.0.1 only. Otherwise people can go around dnsdist.
- Nothing else on port 53. If you ran dnsdist on the host before, stop it first: `systemctl disable --now dnsdist`. Check with `ss -lntup 'sport = :53'`.
- curl or wget on the host, for the blocklist script.

### Setup

1. Read the `setACL` line in `/opt/DNS/dnsdist/dnsdist.conf`. It allows everyone, since this is for a public resolver.

   THIS MAKES YOUR SERVER AN OPEN RESOLVER. On anything that isn't meant to be public, change it to your own ranges first. The comment above it has an example.

2. Make the config readable: `chmod 644 /opt/DNS/dnsdist/dnsdist.conf`
3. Pull the blocklist once, before the first start: `bash /opt/DNS/dnsdist/update-blocklist.sh -n`. That creates `/opt/DNS/dnsdist/blocklist/blocked.txt`. The `-n` skips the restart, since there's nothing running yet. By default it pulls [BlissDNS badips.txt](https://github.com/BlissDNS/info), use `-u` for a different list.
4. Deploy it.
   - Portainer: Stacks, Add stack, name it `dnsdist`, Web editor, paste the contents of `dnsdist/portainer.yml`, Deploy the stack.
   - Terminal: `cd /opt/DNS/dnsdist && docker compose up -d`
5. Add the blocklist update to cron, as root or a user in the docker group: `crontab -e`, then `17 4 * * * bash /opt/DNS/dnsdist/update-blocklist.sh >/dev/null`. That's once a day at 4:17. Errors still get mailed by cron since only stdout is thrown away.

The script checks every line before using it, refuses a list with nothing valid in it, and refuses one that shrank by more than half unless you add `-f`. It only restarts dnsdist when the list actually changed. dnsdist reads the list once at startup, so the restart is how a new list loads. That's about a second where port 53 doesn't answer, and UDP clients retry, so most people won't notice. It also resets the rate limit counters.

### Testing

Run these from a machine outside the server's network, with your server's public address:

- `dig @<server> example.com` should answer.
- `dig @<server> example.com TXT` should show `tc` in the flags and no answer. `dig +tcp @<server> example.com TXT` should answer.
- `dig @<server> example.com ANY` should time out.
- `dig -p 5300 @<server> example.com` should time out. IF IT ANSWERS, ANYONE CAN SKIP DNSDIST.
- Over IPv6 too, if the server has it: `dig -6 @<server> example.com`

On the server:

- `docker logs dnsdist` should show `Loaded N blocklist entries`, listening on 0.0.0.0:53 and [::]:53, and `Marking downstream adguard (127.0.0.1:5300) as 'up'`. If it says `down`, dnsdist can't reach AdGuard Home on 5300.
- `docker top dnsdist` should show dnsdist running as pdns (UID 953), not root.

If dnsdist logs `Address already in use`, something else has port 53. On Ubuntu that can be systemd-resolved's stub listener: set `DNSStubListener=no` in /etc/systemd/resolved.conf and `systemctl restart systemd-resolved`.

## Changing a config

Edit the file in /opt/DNS, then restart that container: `docker restart unbound`, `docker restart pdns-recursor` or `docker restart dnsdist`, or the Restart button in Portainer under Containers. The configs are mounted, so a restart picks up the change. No redeploy needed.

For Unbound, check the config first: `docker exec unbound unbound-checkconf`. A typo stops Unbound from starting.

For dnsdist: `docker exec dnsdist dnsdist --check-config -C /etc/dnsdist/dnsdist.conf`. Same deal, a typo and it won't start.

## Notes

- Neither resolver uses IPv6 for outgoing queries, since Docker bridges don't have IPv6 by default. If you've enabled IPv6 in Docker, set `do-ip6: yes` in unbound.conf and add `- "::"` under `source_address` in recursor.yml.
- `so-rcvbuf: 1m` in unbound.conf only works if the host allows it. If Unbound logs that it wasn't granted, put `net.core.rmem_max = 1048576` in a file under /etc/sysctl.d/ and run `sysctl --system`.
- The rebinding protection blocks loopback too. Domains that point at 127.0.0.1 on purpose, like some local development setups, won't resolve.
- `git pull` in /opt/DNS updates the configs. Restart the containers afterward. If the update changed a portainer.yml, paste the new version into that stack's editor in Portainer too, since Portainer keeps its own copy.
- The blocklist under dnsdist/blocklist/ is generated, so it's in .gitignore and `git pull` never touches it.

Now Unbound and PowerDNS Recursor are both resolving from the root servers with DNSSEC, reachable from the host and anything on dns-net, and closed to everything else. If you run dnsdist, it's on port 53 in front of AdGuard Home, rate limiting and dropping blocklisted addresses before they reach it. Tinker with the cache sizes, thread counts and rate limits as you see fit.
