#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
addons_dir=${1:-${WOW_ADDONS_DIR:-}}
if [[ -z "$addons_dir" ]]; then
  echo 'Usage: bash install.sh "/path/to/World of Warcraft/_forever_/Interface/AddOns"' >&2
  echo 'Alternatively set WOW_ADDONS_DIR to that directory.' >&2
  exit 2
fi
if [[ ! -d "$addons_dir" ]]; then
  echo "AddOns folder not found: $addons_dir" >&2
  exit 1
fi
[[ -f "$source_dir/MobAuction/MobAuction.toc" ]] || { echo 'Source addon missing.' >&2; exit 1; }
staging=$(mktemp -d "$addons_dir/.MobAuction-install.XXXXXX")
backup=''
retired=()
complete=false
cleanup() {
  if [[ "$complete" != true ]]; then
    for name in "${retired[@]}"; do
      mv -- "$backup/$name" "$addons_dir/$name"
    done
  fi
  if [[ -d "$staging" ]]; then rm -rf -- "$staging"; fi
}
trap cleanup EXIT
cp -R -- "$source_dir/MobAuction/." "$staging/"
for name in MobAuction ForgeProfit; do
  if [[ -e "$addons_dir/$name" || -L "$addons_dir/$name" ]]; then
    if [[ -z "$backup" ]]; then
      mkdir -p -- "$addons_dir/.MobAuction-backups"
      backup=$(mktemp -d "$addons_dir/.MobAuction-backups/install.XXXXXX")
    fi
    mv -- "$addons_dir/$name" "$backup/$name"
    retired+=("$name")
  fi
done
mv -- "$staging" "$addons_dir/MobAuction"
complete=true
echo "Installed MobAuction into: $addons_dir/MobAuction"
if [[ -n "$backup" ]]; then echo "Previous addon folders backed up in: $backup"; fi
echo 'Fully restart WoW, enable MobAuction in AddOns, then use /moba or /mobauction.'
