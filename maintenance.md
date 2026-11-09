# Maintenance

Do this every couple of months.

## 1. Update the images

In each folder, `/opt/DNS/unbound` and `/opt/DNS/pdns-recursor`:

- `docker compose pull && docker compose up -d`

Then clean up old images with `docker image prune`.

Updating Unbound also updates its root trust anchor file, since that comes from Alpine's dnssec-root package inside the image. An Unbound image left alone for years can fall behind a root key change and start failing DNSSEC on everything.

## 2. Check for a newer PowerDNS Recursor series

PowerDNS names its images by release series, so `docker compose pull` never moves you from 5.4 to 5.5. Check Docker Hub under the powerdns organization for the highest `pdns-recursor-NN`. If it's newer than the one in pdns-recursor/compose.yml:

1. Read the Recursor upgrade guide for that series, looking for removed or renamed settings.
2. Change the image line, for example `powerdns/pdns-recursor-54` to `powerdns/pdns-recursor-55`.
3. `docker compose up -d`
4. Run the tests in the README.

A series that stops getting releases also stops getting security fixes, so don't skip this.

## 3. Check DNSSEC still works

- `dig @127.0.0.1 -p 5335 dnssec-failed.org` and `dig @127.0.0.1 -p 5354 dnssec-failed.org` should both SERVFAIL.
- `docker exec pdns-recursor rec_control get-tas` should list the current root key.
- If either log shows "Bogus" for `.` or the root, that resolver's image is behind on the root key. Updating the image is the fix.

## 4. Check both resolvers are taking traffic

In Pi-hole or AdGuard Home, check the upstream stats show both resolvers answering. If one shows zero queries or all errors, check `docker logs` for that container.

## 5. Check the ports are still host-only

From another machine on your network:

- `dig -p 5335 @<host-ip> example.com` should time out.
- `dig -p 5354 @<host-ip> example.com` should time out.

If either answers, the `127.0.0.1:` prefix fell off a port line in a compose file.

## 6. Check memory

`docker stats --no-stream unbound pdns-recursor`. Unbound's caches can grow to about 384MB plus overhead. The Recursor counts cache entries, not bytes, so watch it over a few days. Lower `rrset-cache-size` and `msg-cache-size` in unbound.conf, or add `max_entries` under `recordcache` in recursor.yml, if either uses more than you like.

## 7. After editing a config

- Check Unbound's config: `docker exec unbound unbound-checkconf`
- `docker compose up -d --force-recreate` in that folder.
- Run the README tests.
- Add an entry to changes.md.
