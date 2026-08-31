#!/bin/sh
set -eu
# Set:
# - key.priv.asc: ASCII-armored private key
# - KEY_PASSPHRASE: passphrase protecting key, default ""
# - PUBLISH_URL: (optional) URL repo will be accessible from

WORK_DIR="./_build"
PROJECT_NAME="$(basename $(dirname $(readlink -f "$0")))"
PROJECT_REL="sid"
PROJECT_SUITE="unstable"
KEY_PASSPHRASE="${KEY_PASSPHRASE-}"

# Make temporary repo dir so we can modify configs
[ -d "${WORK_DIR}" ] && rm -r "${WORK_DIR}"
REPO_DIR="${WORK_DIR}/repo"
mkdir -p -- "${REPO_DIR}"

# Work out PUBLISH_URL from git origin
if [ -n "${PUBLISH_URL-}" ]; then
  # Already got one, do nothing
  export PUBLISH_URL
elif git remote get-url origin | grep -qE '^git@github.com:'; then
  export PUBLISH_URL="$(git remote get-url origin | awk 'FS="/" { sub("git@github.com:", "") ; print "https://" $1 ".github.io/" $2 }')"
fi

# Import key into temporary keyring
export GNUPGHOME="$(mktemp -d)"
echo "${KEY_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --import "key.priv.asc"
export KEY_AUTHOR="$(gpg --list-secret-keys | awk '/^uid/ { sub("^.*\] *", "") ; print }')"
export KEY_EMAIL="$(echo "${KEY_AUTHOR}"| sed 's/.*<// ; s/>.*//')"
[ -z "${KEY_AUTHOR-}" ] && { echo "No GPG key imported"; exit 1; }

# Build rerepro config
mkdir -p "${REPO_DIR}/conf"
cat <<EOF > "${REPO_DIR}/conf/distributions"
# https://wiki.debian.org/DebianRepository/SetupWithReprepro
# https://manpages.debian.org/trixie/reprepro/reprepro.1.en.html#conf/distributions
Origin: ${PROJECT_NAME}
Label: ${PROJECT_NAME}
Codename: ${PROJECT_REL}
Suite: ${PROJECT_SUITE}
Architectures: source i386 amd64 arm64
Components: main
Description: ${PROJECT_NAME} repository at ${PUBLISH_URL}
# NB: reprepro doesn't handle spaces
SignWith: ${KEY_EMAIL}
EOF

reprepro -b "${REPO_DIR}" createsymlinks
reprepro -b "${REPO_DIR}" export

# Build quickpkg-based packages
for f in *.cfg; do
  ./quickpkg.py "${WORK_DIR}" "$f" "${PROJECT_REL}"
done

# Build package scripts
for f in ./*.pkg.sh; do
  "$f" "${WORK_DIR}" "${PROJECT_REL}"
done

handled=""
for PKG_FILE in "${WORK_DIR}/"*.changes; do
  reprepro -b "${REPO_DIR}" include "${PROJECT_REL}" "${PKG_FILE}"
  handled="${handled} $(awk '/^Files:/ { sect=1 } sect==1 && /.deb$/ { print $5 }' "${PKG_FILE}")"
done

for PKG_FILE in "${WORK_DIR}/"*.deb; do
  echo "${handled}" | grep -qw "$(basename "${PKG_FILE}")" && continue
  reprepro -b "${REPO_DIR}" includedeb "${PROJECT_REL}" "${PKG_FILE}"
done
