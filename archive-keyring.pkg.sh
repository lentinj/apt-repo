#!/bin/sh
# Adapted from https://wiki.debian.org/DebianRepository/SetupWithReprepro
PROJECT="$(awk '/^Origin:/ { print $2 }' ./repo/conf/distributions)"
WORK_DIR="$1"
DEB_DIR="${WORK_DIR}/${PROJECT}-archive-keyring"

mkdir -p "${DEB_DIR}/debian"
# TODO: Flag file to get the author from git?
cat > "${DEB_DIR}/debian/control" <<EOF
Package: $PROJECT-archive-keyring
Version: 1.0.0-1
Section: misc
Priority: optional
Architecture: all
Maintainer: $(git log --pretty=format:'%an <%ae>' | head -1)
Description: OpenPGP archive certificates of $PROJECT
 $PROJECT digitally signs its Release files. This package
 contains the archive certificates used for that.
EOF

# TODO: Export / import key: https://stackoverflow.com/a/61748039
# https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key

mkdir -p "${DEB_DIR}/usr/share/keyrings"
gpg --export-options export-minimal --export <fingerprint> \
    > "${DEB_DIR}/usr/share/keyrings/$PROJECT.pgp"

mkdir -p "${DEB_DIR}/etc/apt/sources.list.d"
for REL in $(awk '/^Codename:/ { print $2 }' "${REPO_DIR}/conf/distributions"); do
  # TODO: Fish out components for this codename
  # TODO: 
  cat >> "${DEB_DIR}/etc/apt/sources.list.d/${PROJECT}.list" <<EOF
deb [signed-by=/usr/share/keyrings/$PROJECT.pgp] http://<your-domain>/<your-path>/ ${REL} $(awk '/^Components:/ { print $2 $3 $4 $5 $6 $7 }' repo/conf/distributions| head -1)
EOF
done

dpkg-deb --root-owner-group --build "${WORK_DIR}/${PROJECT}-archive-keyring"
