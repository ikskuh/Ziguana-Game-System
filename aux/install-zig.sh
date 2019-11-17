#!/bin/bash

REPO_URL=https://ziglang.org/download/index.json
TMPDIR=/tmp/zig-update

REPO_ENTRY=x86_64-linux

function die()
{
	echo "$@"
	rm -r ${TMPDIR}
	exit 1
}

REPO="${TMPDIR}/zig-repo.json"

mkdir -p "${TMPDIR}"

echo "Downloading repository..."

curl -s "${REPO_URL}" | jq ".master[\"${REPO_ENTRY}\"]" > "${REPO}" || die "failed to aquire repo!"

TARBALL=$(jq --raw-output '.tarball' ${REPO})
SHASUM=$(jq --raw-output '.shasum' ${REPO})
SIZE=$(jq --raw-output '.size' ${REPO})

VERSION=$(basename ${TARBALL} | sed 's/.tar.xz$//')

[ "${VERSION}" != "" ] || die "Could not extract version info"

echo "Updating to ${VERSION}"

curl "${TARBALL}" | tar -xJ || die "failed to extract zig!"

mv ${VERSION} zig-current || die "failed to move folder"

echo "Current version is now: $(./zig-current/zig version)"

rm -r ${TMPDIR}
