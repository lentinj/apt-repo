#!/bin/sh
set -eu
# https://gock.net/blog/2020/gpg-cheat-sheet
# https://www.gnupg.org/documentation/manuals/gnupg-devel/Unattended-GPG-key-generation.html

KEY_USER="${1}"
KEY_EMAIL="${2}"

export GNUPGHOME="$(mktemp -d)"

cat <<EOF | gpg --batch --generate-key -
     Key-Type: RSA
     Key-Length: 4098
     Name-Real: ${KEY_USER}
     Name-Email: ${KEY_EMAIL}
     Expire-Date: 0
     %no-protection
     %commit
     %echo done
EOF
gpg --list-secret-keys 
gpg --armor --export-secret-keys > key.priv.asc
