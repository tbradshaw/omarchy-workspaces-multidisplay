#!/usr/bin/env bash
# Static checks for the plugin. Nothing here loads the plugin into the
# running shell.

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_shell=${OMARCHY_PATH:-/usr/share/omarchy}/shell

omarchy plugin validate "$plugin_dir"

jq -e '
  .schemaVersion == 1
  and .id == "io.github.tbradshaw.workspaces-multidisplay"
  and (.kinds | index("bar-widget") != null)
  and .entryPoints.barWidget == "Workspaces.qml"
  and .omarchy.clonedFrom == "omarchy.workspaces"
' "$plugin_dir/manifest.json" >/dev/null

module_name=$(sed -n 's/^  moduleName: "\(.*\)"$/\1/p' "$plugin_dir/Workspaces.qml")
manifest_id=$(jq -r .id "$plugin_dir/manifest.json")
if [[ "$module_name" != "$manifest_id" ]]; then
  echo "moduleName ($module_name) does not match manifest id ($manifest_id)" >&2
  exit 1
fi

# Quickshell resolves `qs.*` imports against the shell root, so expose the
# Omarchy shell to qmllint under the name `qs`.
import_root=$(mktemp -d)
trap 'rm -rf "$import_root"' EXIT
ln -s "$omarchy_shell" "$import_root/qs"

qmllint=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
"$qmllint" -I "$import_root" -I /usr/lib/qt6/qml "$plugin_dir/Workspaces.qml"

if [[ -f "$plugin_dir/tests/MonitorLayout.test.js" ]]; then
  node --test "$plugin_dir/tests/"
fi

echo "All checks passed."
