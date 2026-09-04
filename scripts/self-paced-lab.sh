#!/usr/bin/env bash
set -euo pipefail

module=''
workspace_root="${HOME}/Data2AI-Labs"
validator_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) module="$2"; shift 2 ;;
    --workspace-root) workspace_root="$2"; shift 2 ;;
    --all|--report) validator_args+=("$1"); shift ;;
    --task) validator_args+=("$1" "$2"); shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ "$module" =~ ^[0-9]+$ ]] || { printf 'Use --module 0..14\n' >&2; exit 2; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf -v module_num '%02d' "$module"
shopt -s nullglob
module_dirs=("$repo_root"/student-track/module-"$module_num"-*)
(( ${#module_dirs[@]} == 1 )) || { printf 'Expected one student-track module for M%s\n' "$module_num" >&2; exit 1; }
module_dir="${module_dirs[0]}"
module_name="$(basename "$module_dir")"
workspace="$workspace_root/$module_name"
[[ -d "$workspace" ]] || { printf 'Workspace not found: %s\nRun new-student-workspace.sh first.\n' "$workspace" >&2; exit 1; }
[[ -x "$module_dir/validate.sh" || -f "$module_dir/validate.sh" ]] || { printf 'Validator not found: %s/validate.sh\n' "$module_dir" >&2; exit 1; }

export STUDENT_WORKSPACE="$workspace"
export STUDENT_MODULE_DIR="$module_dir"
export STUDENT_MODULE_NUM="$module_num"
if [[ -f "$workspace/.student-workspace.json" ]] && command -v python3 >/dev/null 2>&1; then
  STUDENT_INITIALS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["initials"])' "$workspace/.student-workspace.json")"
else
  STUDENT_INITIALS='STUDENT'
fi
export STUDENT_INITIALS

cd "$workspace"
bash "$module_dir/validate.sh" "${validator_args[@]}"
