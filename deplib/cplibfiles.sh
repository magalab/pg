#!/bin/sh
set -eu

binary=$1
out_dir=$2
mkdir -p "$out_dir"

if ! ldd_output=$(ldd "$binary" 2>&1); then
	printf 'Unable to inspect shared libraries for %s:\n%s\n' "$binary" "$ldd_output" >&2
	exit 1
fi

missing=$(printf '%s\n' "$ldd_output" | awk '/not found/ { print $1 }')
if [ -n "$missing" ]; then
	printf 'Missing shared libraries for %s:\n%s\n' "$binary" "$missing" >&2
	exit 1
fi

dependencies=$(printf '%s\n' "$ldd_output" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
while IFS= read -r lib_file; do
	[ -n "$lib_file" ] || continue
	lib_dir="$out_dir$(dirname "$lib_file")"
	mkdir -p "$lib_dir"
	printf 'Copying %s -> %s%s\n' "$lib_file" "$out_dir" "$lib_file"
	cp -L -n "$lib_file" "$out_dir$lib_file"
done <<EOF
$dependencies
EOF
