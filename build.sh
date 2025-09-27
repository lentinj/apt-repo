#!/bin/sh
set -eu

REPO_DIR="./repo"
WORK_DIR="./work"

[ -d "${WORK_DIR}" ] && rm -r "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# TODO: Splice key into conf

echo reprepro -b "${REPO_DIR}" createsymlinks
echo reprepro -b "${REPO_DIR}" export

# Build quickpkg-based packages
for f in *.cfg; do
  ./quickpkg.py "${WORK_DIR}" "$f"
done

# Build package scripts
for f in *.pkg.sh; do
  "$f" "${WORK_DIR}"
done

handled=""
for "${PKG_FILE}" in "${WORK_DIR}/*.changes"; do
  for REL in $(awk '/^Codename:/ { print $2 }' "${REPO_DIR}/conf/distributions"); do
    echo reprepro -b "${REPO_DIR}" include "${REL}" "${PKG_FILE}"
  done
  handled="${handled} $(awk '/^Files:/ { sect=1 } sect==1 && /.deb$/ { print $5 }' "${PKG_FILE}")"
done

for "${PKG_FILE}" in "${WORK_DIR}/*.deb"; do
  echo "${handled}" | grep -qw "$(basename "${PKG_FILE}")" && continue
  for REL in $(awk '/^Codename:/ { print $2 }' "${REPO_DIR}/conf/distributions"); do
    echo reprepro -b "${REPO_DIR}" include "${REL}" "${PKG_FILE}"
  done
done
