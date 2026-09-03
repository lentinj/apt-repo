#!/bin/sh
set -eu
# Set:
# - KEY_PRIVKEY: Conent of ASCII-armored private key
# - KEY_PASSPHRASE: passphrase protecting key, default ""
# - PUBLISH_URL: (optional) URL repo will be accessible from

WORK_DIR="./_build"
PROJECT_NAME="$(basename "$(dirname "$(readlink -f "$0")")")"
PROJECT_REL="sid"
PROJECT_SUITE="unstable"
KEY_PASSPHRASE="${KEY_PASSPHRASE-}"
export WORK_DIR PROJECT_NAME PROJECT_REL PROJECT_SUITE

# Make temporary repo dir so we can modify configs
[ -d "${WORK_DIR}" ] && rm -r "${WORK_DIR}"
REPO_DIR="${WORK_DIR}/repo"
mkdir -p -- "${REPO_DIR}"

# Work out PUBLISH_URL from git origin
if [ -n "${PUBLISH_URL-}" ]; then
  # Already got one, do nothing
  true
elif git remote get-url origin | grep -qE '^git@github.com:'; then
  PUBLISH_URL="$(git remote get-url origin | awk 'FS="/" { sub("git@github.com:", "") ; print "https://" $1 ".github.io/" $2 }')"
elif git remote get-url origin | grep -qE '^https://github.com'; then
  PUBLISH_URL="$(git remote get-url origin | awk 'FS="/" { sub("https://github.com/", "") ; print "https://" $1 ".github.io/" $2 }')"
else
  echo "Cannot convert git origin to a publish URL"
  git remote -v
  exit 1
fi
export PUBLISH_URL

# Import key into temporary keyring
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
if [ -n "${KEY_PRIVKEY-}" ]; then
  printf "%s" "${KEY_PRIVKEY}" | gpg --batch --yes --import -
elif [ -e "key.priv.asc" ]; then
  echo "${KEY_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --import "key.priv.asc"
else
  echo "KEY_PRIVKEY or key.priv.asc not available"
  exit 1
fi
gpg --list-secret-keys
KEY_AUTHOR="$(gpg --list-secret-keys | awk '/^uid/ { sub("^.*] *", "") ; print }')"
KEY_EMAIL="$(echo "${KEY_AUTHOR}"| sed 's/.*<// ; s/>.*//')"
[ -z "${KEY_AUTHOR-}" ] && { echo "No GPG key imported"; exit 1; }
export KEY_AUTHOR KEY_EMAIL

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

for f in packages/*; do
  echo ================================== "$f" ===
  case $f in
    *.cfg)
      python3 ./quickpkg.py "${WORK_DIR}" "$f" "${PROJECT_REL}"
      ;;
    *.sh)
      "$f" "${WORK_DIR}" "${PROJECT_REL}"
      ;;
    *)
      echo "Don't know how to build $f"
      exit 1
      ;;
  esac
done
echo ==================================

handled=""
for PKG_FILE in "${WORK_DIR}/"*.changes; do
  reprepro -b "${REPO_DIR}" include "${PROJECT_REL}" "${PKG_FILE}"
  handled="${handled} $(awk '/^Files:/ { sect=1 } sect==1 && /.deb$/ { print $5 }' "${PKG_FILE}")"
done

for PKG_FILE in "${WORK_DIR}/"*.deb; do
  echo "${handled}" | grep -qw "$(basename "${PKG_FILE}")" && continue
  reprepro -b "${REPO_DIR}" includedeb "${PROJECT_REL}" "${PKG_FILE}"
done

# Generate index.html
URL_CONFIG_DEB="$(find _build/repo/ -name 'apt-repo-archive-keyring_*.deb' | sed "sx_build/repox${PUBLISH_URL}x")"
cat <<EOF > _build/repo/index.html
<html>
<body>

<h1>${PROJECT_NAME} repository</h1>
<p>To install:</p>
<pre>
wget ${URL_CONFIG_DEB}
dpkg -i $(basename ${URL_CONFIG_DEB})
</pre>

</body>
</html>
EOF
