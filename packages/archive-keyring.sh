#!/bin/sh
# Adapted from https://wiki.debian.org/DebianRepository/SetupWithReprepro
set -eu

WORK_DIR="$1"
REPO_DIR="${WORK_DIR}/repo"
PROJECT="$(awk '/^Origin:/ { print $2 }' "${REPO_DIR}/conf/distributions")"
DEB_DIR="${WORK_DIR}/${PROJECT}-archive-keyring"

mkdir -p "${DEB_DIR}/DEBIAN"
# TODO: Flag file to get the author from git?
cat > "${DEB_DIR}/DEBIAN/control" <<EOF
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

mkdir -p "${DEB_DIR}/usr/share/keyrings"
gpg --export-options export-minimal --export "${KEY_AUTHOR}" \
    > "${DEB_DIR}/usr/share/keyrings/$PROJECT.pgp"

# NB: Assuming KEY_AUTHOR is set
mkdir -p "${DEB_DIR}/etc/apt/sources.list.d"
for REL in $(awk '/^Codename:/ { print $2 }' "${REPO_DIR}/conf/distributions"); do
  COMPONENTS="$(awk '/^Components:/ {  sub("^Components: *", "") ; print }' repo/conf/distributions| head -1)"
  cat >> "${DEB_DIR}/etc/apt/sources.list.d/${PROJECT}.list" <<EOF
deb [signed-by=/usr/share/keyrings/$PROJECT.pgp] http://<your-domain>/<your-path>/ ${REL} ${COMPONENTS}
EOF
done

dpkg-deb --root-owner-group --build "${WORK_DIR}/${PROJECT}-archive-keyring"
