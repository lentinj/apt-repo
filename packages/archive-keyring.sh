#!/bin/sh
# Adapted from https://wiki.debian.org/DebianRepository/SetupWithReprepro
set -eu

WORK_DIR="$1"
REPO_DIR="${WORK_DIR}/repo"
PROJECT="$(awk '/^Origin:/ { print $2 }' "${REPO_DIR}/conf/distributions")"
DEB_DIR="${WORK_DIR}/${PROJECT}-archive-keyring"

mkdir -p "${DEB_DIR}/DEBIAN"
cat > "${DEB_DIR}/DEBIAN/control" <<EOF
Package: $PROJECT-archive-keyring
Version: 1
Section: misc
Priority: optional
Architecture: all
Maintainer: ${KEY_AUTHOR}
Description: OpenPGP archive certificates of $PROJECT
 $PROJECT digitally signs its Release files. This package
 contains the archive certificates used for that.
EOF

# NB: Assuming KEY_AUTHOR is set
mkdir -p "${DEB_DIR}/usr/share/keyrings"
gpg --export-options export-minimal --export "${KEY_AUTHOR}" \
    > "${DEB_DIR}/usr/share/keyrings/$PROJECT.pgp"

mkdir -p "${DEB_DIR}/etc/apt/sources.list.d"

COMPONENTS="$(awk '/^Components:/ {  sub("^Components: *", "") ; print }' "${REPO_DIR}/conf/distributions" | head -1)"
cat >> "${DEB_DIR}/etc/apt/sources.list.d/${PROJECT}.sources" <<EOF
Types: deb
URIs: ${PUBLISH_URL}
Suites: ${PROJECT_REL}
Components: ${COMPONENTS}
Signed-By: /usr/share/keyrings/$PROJECT.pgp
EOF

dpkg-deb --root-owner-group --build "${WORK_DIR}/${PROJECT}-archive-keyring"
