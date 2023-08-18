#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
	echo "Please provide a tag."
	echo "Usage: ./release.sh v[X.Y.Z]"
	exit
fi

echo "Preparing $1..."
# update the version
msg="\/\/ managed by release.sh"
sed -E -i "s/^(const version = ).* $msg$/\1\"${1#v}\"; $msg/" build.zig
zig build --summary all test
# update the changelog
git cliff --tag "$1" >CHANGELOG.md
git add -A
git commit -m "chore(release): prepare for $1"
git show
# generate a changelog for the tag message
changelog=$(git cliff --tag "$1" --unreleased --strip all | sed -e '/^#/d' -e '/^$/d')
# create a signed tag
# https://keyserver.ubuntu.com/pks/lookup?search=0xC0701E98290D90B8&op=vindex
git -c user.name="linuxwave" \
	-c user.email="linuxwave@protonmail.com" \
	-c user.signingkey="21B6926360C8A0C82C48155DC0701E98290D90B8" \
	tag -f -s -a "$1" -m "Release $1" -m "$changelog"
git tag -v "$1"
echo "Done!"
echo "Now push the commit (git push) and the tag (git push --tags)."
