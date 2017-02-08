#!/bin/bash
##
## Ansible: Setup user's local Ansible environment
## Copyright (c) 2017 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
umask 0022

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <SETUPDIR>"
  exit 1
fi

ansible_root="$1"; shift
if [[ $ansible_root != /* ]]; then
  ansible_root="$PWD/$ansible_root"
fi

python="${python:-python}"
python_modules=(
  ansible${ansible_version:+==$ansible_version}
  paramiko${paramiko_version:+==$paramiko_version}
  pyyaml${pyyaml_version:+==$pyyaml_version}
  jinja2${jinja2_version:+==$jinja2_version}
  httplib2${httplib2_version:+==$httplib2_version}
  six${six_version:+==$six_version}
  pywinrm${pywinrm_version:+==$pywinrm_version}
)

## Setup pip
## ======================================================================

export PYTHONUSERBASE="$ansible_root"
export XDG_CACHE_HOME="$ansible_root/var/cache/xdg"

mkdir -p "$ansible_root/bin" || exit 1
cd "$ansible_root/bin" || exit 1
wget --timestamping https://bootstrap.pypa.io/get-pip.py || exit 1
"$python" get-pip.py --user || exit 1

## Setup Ansible
## ======================================================================

python_sitelib=$(echo "$ansible_root"/lib/python*/*)
export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"

pip install --user --ignore-installed "${python_modules[@]}" || exit 1

## Create env-setup script
## ======================================================================

cat <<EOF >env-setup || exit 1
ansible_root="$ansible_root"
EOF

cat <<'EOF' >>env-setup || exit 1
if [[ -n ${ZSH_VERSION-} ]]; then
  ansible_root=$(cd "${0%/*}/.." && pwd) || return 1
elif [[ -n ${BASH_VERSION-} ]]; then
  ansible_root=$(cd "${BASH_SOURCE[0]%/*}"/.. && pwd) || return 1
fi

python_sitelib=$(echo "$ansible_root"/lib/python*/*)

export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"
EOF

exit 0
