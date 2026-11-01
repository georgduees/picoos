#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=2026.05.3
archive="buildroot-${version}.tar.gz"
sha256=b824356cca57d744b14f56812e96ca243be815da7c21b76a281b33c65065fb73

mkdir -p "$project_dir/dl" "$project_dir/buildroot"

if [ -f "$project_dir/buildroot/Makefile" ]; then
	if grep -Fq "export BR2_VERSION := ${version}" "$project_dir/buildroot/Makefile"; then
		printf 'Buildroot %s is already present.\n' "$version"
		exit 0
	fi
	printf 'Refusing to use an existing, unexpected Buildroot tree: %s\n' "$project_dir/buildroot" >&2
	exit 1
fi

archive_path="$project_dir/dl/$archive"
if [ ! -f "$archive_path" ]; then
	curl --fail --location --retry 3 \
		--output "$archive_path" \
		"https://buildroot.org/downloads/$archive"
fi

printf '%s  %s\n' "$sha256" "$archive_path" | sha256sum --check --status || {
	printf 'SHA-256 verification failed for %s\n' "$archive_path" >&2
	exit 1
}

tar -xzf "$archive_path" --strip-components=1 -C "$project_dir/buildroot"
printf 'Verified and unpacked Buildroot %s.\n' "$version"
