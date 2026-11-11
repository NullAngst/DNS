# Maintenance

Do this every couple of months. Each step has the Portainer way and the terminal way, so use whichever you deployed with.

## 1. Update the repo

- `cd /opt/DNS && git pull`
- If anything in a config changed, restart that container (step 7).
- If a portainer.yml changed, open that stack in Portainer, click Editor, paste the new version, and Update the stack. Portainer keeps its own copy of the stack and won't see the change otherwise.

## 2. Update the images

Portainer: open each stack, click Editor, then Update the stack with "Re-pull image and redeploy" turned on.

Terminal: in `/opt/DNS/unbound` and `/opt/DNS/pdns-recursor`, and `/opt/DNS/dnsdist` if you run it, run `docker compose pull && docker compose up -d`.

Then clean up old images with `docker image prune`, or Images, then Remove unused in Portainer.

Unbound's root trust anchor comes from the host, not the image, so also update the host's packages. I use apt, so in my case `apt update && apt upgrade`, which keeps dns-root-data current. Use whichever package manager your system has. A stale root key makes Unbound SERVFAIL on everything after the next root key change.

## 3. Check for a newer PowerDNS Recursor series

PowerDNS names its images by release series, so pulling never moves you from 5.4 to 5.5. Check Docker Hub under the powerdns organization for the highest `pdns-recursor-NN`. If it's newer than the one you're running:

1. Read the Recursor upgrade guide for that series, looking for removed or renamed settings in recursor.yml.
2. Change the image line in both `pdns-recursor/compose.yml` and `pdns-recursor/portainer.yml`, for example `powerdns/pdns-recursor-54` to `powerdns/pdns-recursor-55`, and commit it.
3. Portainer: paste the new portainer.yml into the stack's editor and Update the stack with re-pull on. Terminal: `docker compose up -d` in `/opt/DNS/pdns-recursor`.
4. Run the tests in the README.
5. Add an entry to changes.md.

A series that stops getting releases also stops getting security fixes, so don't skip this.

## 3.5. Check for a newer dnsdist series

Same naming: `powerdns/dnsdist-21` is 2.1.x. Look for a higher `dnsdist-NN` under the powerdns organization on Docker Hub, but check the changelog at dnsdist.org before moving to it. PowerDNS publishes the image for a new series while it's still in alpha and beta, so an image existing doesn't mean the series is released. Wait for the .0 final.

1. Read the dnsdist upgrade guide for that series, looking for removed or renamed Lua functions used in dnsdist.conf.
2. Change the image line in both `dnsdist/compose.yml` and `dnsdist/portainer.yml` and commit it.
3. Portainer: paste the new portainer.yml into the dnsdist stack's editor and Update the stack with re-pull on. Terminal: `docker compose up -d` in `/opt/DNS/dnsdist`.
4. Run the dnsdist tests in the README.
5. Add an entry to changes.md.

Since 2.1, dnsdist looks for dnsdist.yml before dnsdist.conf. The compose files pass `--config /etc/dnsdist/dnsdist.conf`, so that doesn't matter here. Keep that flag.

## 4. Check DNSSEC still works

- `dig @127.0.0.1 -p 5335 dnssec-failed.org` and `dig @127.0.0.1 -p 5354 dnssec-failed.org` should both SERVFAIL.
- `docker exec pdns-recursor rec_control get-tas` should list the current root key.
- `grep -c 38696 /usr/share/dns/root.key` on the host should print 1. That's Unbound's root key. When the root zone moves to a newer key, this check needs the new key tag, which ICANN announces well in advance.
- If either log shows "Bogus" or validation failures for `.`, that resolver is behind on the root key. For Unbound, update dns-root-data on the host and restart the container. For the Recursor, update the image.

## 4.5. Check the router isn't hijacking DNS

From the host: `dig @198.41.0.4 . NS +norec` should show `aa` and 13 root servers. Router firmware updates can wipe the exclusion, and then both resolvers fail. See "Router DNS redirects" in the README.

## 5. Check both resolvers are taking traffic

In Pi-hole or AdGuard Home, check the upstream stats show both resolvers answering. If one shows zero queries or all errors, check that container's logs.

## 6. Check the ports are still host-only

From another machine on your network:

- `dig -p 5335 @<host-ip> example.com` should time out.
- `dig -p 5354 @<host-ip> example.com` should time out.

If either answers, the `127.0.0.1:` prefix fell off a port line. Check both the file in the repo and the copy in Portainer's stack editor, since they can drift apart.

If you run dnsdist, also from outside the server's network:

- `dig -p 5300 @<server> example.com` should time out. If it answers, AdGuard Home's plain DNS port is open and people can go around dnsdist.
- `dig @<server> example.com TXT` should come back with `tc` set and no answer. If it answers, the dnsdist rules aren't loaded or something other than dnsdist has port 53.

## 6.5. Check the dnsdist blocklist

- Run `bash /opt/DNS/dnsdist/update-blocklist.sh` by hand. It should say the list is unchanged or updated. A download error or a refusal means the cron job has been failing too.
- `docker logs dnsdist 2>&1 | grep blocklist` should show the loaded count and no "Skipping invalid" lines. The script already filters bad lines, so any there means the file was edited by hand.
- `crontab -l` should still have the update line.

## 7. Check memory

`docker stats --no-stream unbound pdns-recursor dnsdist`, or the container stats page in Portainer. dnsdist has no cache configured, so it should stay small. Unbound's caches can grow to about 384MB plus overhead. The Recursor counts cache entries, not bytes, so watch it over a few days. Lower `rrset-cache-size` and `msg-cache-size` in unbound.conf, or add `max_entries` under `recordcache` in recursor.yml, if either uses more than you like.

## 8. After editing a config

- For Unbound, check it first: `docker exec unbound unbound-checkconf`
- For dnsdist, check it first: `docker exec dnsdist dnsdist --check-config -C /etc/dnsdist/dnsdist.conf`
- Restart the container: `docker restart unbound`, `docker restart pdns-recursor` or `docker restart dnsdist`, or Restart in Portainer under Containers.
- Run the README tests.
- Add an entry to changes.md.

## 9. Keep compose.yml and portainer.yml in sync

They should only differ in the volume paths and the comment at the top. Any change to an image, port, IP or network goes in both. To check, from /opt/DNS:

`diff unbound/compose.yml unbound/portainer.yml`, `diff pdns-recursor/compose.yml pdns-recursor/portainer.yml` and `diff dnsdist/compose.yml dnsdist/portainer.yml`

Anything showing up besides the header comment and the `volumes` lines is drift.
