# Maintenance

Do this every couple of months. Each step has the Portainer way and the terminal way, so use whichever you deployed with.

## 1. Update the repo

- `cd /opt/DNS && git pull`
- If anything in a config changed, restart that container (step 7).
- If a portainer.yml changed, open that stack in Portainer, click Editor, paste the new version, and Update the stack. Portainer keeps its own copy of the stack and won't see the change otherwise.

## 2. Update the images

Portainer: open each stack, click Editor, then Update the stack with "Re-pull image and redeploy" turned on.

Terminal: in `/opt/DNS/unbound` and `/opt/DNS/pdns-recursor`, run `docker compose pull && docker compose up -d`.

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

## 7. Check memory

`docker stats --no-stream unbound pdns-recursor`, or the container stats page in Portainer. Unbound's caches can grow to about 384MB plus overhead. The Recursor counts cache entries, not bytes, so watch it over a few days. Lower `rrset-cache-size` and `msg-cache-size` in unbound.conf, or add `max_entries` under `recordcache` in recursor.yml, if either uses more than you like.

## 8. After editing a config

- For Unbound, check it first: `docker exec unbound unbound-checkconf`
- Restart the container: `docker restart unbound` or `docker restart pdns-recursor`, or Restart in Portainer under Containers.
- Run the README tests.
- Add an entry to changes.md.

## 9. Keep compose.yml and portainer.yml in sync

They should only differ in the volume paths and the comment at the top. Any change to an image, port, IP or network goes in both. To check, from /opt/DNS:

`diff unbound/compose.yml unbound/portainer.yml` and `diff pdns-recursor/compose.yml pdns-recursor/portainer.yml`

Anything showing up besides the header comment and the `volumes` lines is drift.
