#!/usr/bin/env bash
# Pull the bad IP list, check every line, write it to blocklist/blocked.txt and
# restart the dnsdist container if the list changed.
#
# Usage: bash update-blocklist.sh [-u url] [-c container] [-f] [-n]
#   -u URL        list to download (default: BlissDNS badips.txt)
#   -c NAME       container to restart (default: dnsdist)
#   -f            write the list even if it shrank by more than half
#   -n            write the list but don't restart the container

set -euo pipefail
export LC_ALL=C

url="https://raw.githubusercontent.com/BlissDNS/info/main/badips.txt"
container="dnsdist"
force=0
restart=1

usage() {
	printf 'Usage: %s [-u url] [-c container] [-f] [-n]\n' "$0" >&2
	exit 2
}

while getopts 'u:c:fnh' opt; do
	case "$opt" in
		u) url="$OPTARG" ;;
		c) container="$OPTARG" ;;
		f) force=1 ;;
		n) restart=0 ;;
		*) usage ;;
	esac
done

missing=""
for cmd in awk cmp dirname mktemp mv chmod mkdir wc; do
	command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
if [ "$restart" -eq 1 ] && ! command -v docker >/dev/null 2>&1; then
	missing="$missing docker"
fi
if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL --max-time 60 -o "$2" -- "$1"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -q -T 60 -O "$2" -- "$1"; }
else
	missing="$missing curl-or-wget"
fi
if [ -n "$missing" ]; then
	printf 'Missing required commands:%s\n' "$missing" >&2
	exit 1
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1
list_dir="$script_dir/blocklist"
target="$list_dir/blocked.txt"

download=""
staging=""
cleanup() {
	[ -n "$download" ] && rm -f -- "$download"
	[ -n "$staging" ] && rm -f -- "$staging"
	return 0
}
trap cleanup EXIT

mkdir -p -- "$list_dir"
chmod 755 -- "$list_dir"

download=$(mktemp "${TMPDIR:-/tmp}/badips.XXXXXX")
if ! fetch "$url" "$download"; then
	printf 'Download failed: %s\n' "$url" >&2
	exit 1
fi

# Staged next to the target so the final mv is an atomic rename
staging=$(mktemp "$list_dir/.blocked.XXXXXX")

# Keep lines that are a valid IPv4 or IPv6 address, with or without a prefix.
# Comments and blank lines are dropped. Bad lines go to stderr and get counted.
bad=$(awk -v out="$staging" '
	function v4(s,   t, a, n, i) {
		if (index(s, "/")) {
			split(s, t, "/")
			if (t[2] !~ /^[0-9]+$/ || t[2] + 0 > 32) return 0
			s = t[1]
		}
		n = split(s, a, ".")
		if (n != 4) return 0
		for (i = 1; i <= 4; i++)
			if (a[i] !~ /^[0-9]+$/ || a[i] + 0 > 255) return 0
		return 1
	}
	function v6(s,   t, a, n, i, rest) {
		if (index(s, "/")) {
			split(s, t, "/")
			if (t[2] !~ /^[0-9]+$/ || t[2] + 0 > 128) return 0
			s = t[1]
		}
		if (s !~ /:/ || s !~ /^[0-9a-fA-F:]+$/) return 0
		rest = s
		if (sub(/::/, "", rest) && rest ~ /::/) return 0
		n = split(s, a, ":")
		if (n > 8) return 0
		for (i = 1; i <= n; i++)
			if (length(a[i]) > 4) return 0
		return 1
	}
	{
		sub(/#.*/, "")
		gsub(/[ \t\r]/, "")
		if ($0 == "") next
		if (v4($0) || v6($0)) print > out
		else { printf "Skipping invalid line %d: %s\n", NR, $0 > "/dev/stderr"; bad++ }
	}
	END { print bad + 0 }
' "$download")

new_count=$(wc -l <"$staging")
new_count=$((new_count + 0))
if [ "$new_count" -eq 0 ]; then
	printf 'No valid entries in %s, leaving the current list alone\n' "$url" >&2
	exit 1
fi

old_count=0
if [ -f "$target" ]; then
	old_count=$(wc -l <"$target")
	old_count=$((old_count + 0))
fi

if [ "$force" -eq 0 ] && [ $((new_count * 2)) -lt "$old_count" ]; then
	printf 'New list has %d entries, down from %d. Not replacing it. Run with -f if that is right.\n' \
		"$new_count" "$old_count" >&2
	exit 1
fi

if [ -f "$target" ] && cmp -s -- "$staging" "$target"; then
	printf 'Blocklist unchanged, %d entries\n' "$new_count"
	exit 0
fi

chmod 644 -- "$staging"
mv -f -- "$staging" "$target"
staging=""
printf 'Blocklist updated: %d entries (was %d), %d invalid lines skipped\n' "$new_count" "$old_count" "$bad"

[ "$restart" -eq 1 ] || exit 0

running=$(docker inspect -f '{{.State.Running}}' -- "$container" 2>/dev/null || true)
if [ "$running" = "true" ]; then
	docker restart -- "$container" >/dev/null
	printf 'Restarted %s\n' "$container"
else
	printf '%s is not running, the new list loads when it starts\n' "$container"
fi
