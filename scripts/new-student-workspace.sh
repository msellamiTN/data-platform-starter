#!/usr/bin/env bash
set -euo pipefail

module=''
initials=''
workspace_root="${HOME}/Data2AI-Labs"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) module="$2"; shift 2 ;;
    --initials) initials="$2"; shift 2 ;;
    --workspace-root) workspace_root="$2"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ "$module" =~ ^[0-9]+$ ]] || { printf 'Use --module 0..14\n' >&2; exit 2; }
(( module >= 0 && module <= 14 )) || { printf 'Module must be between 0 and 14\n' >&2; exit 2; }
[[ "$initials" =~ ^[A-Z]{2,4}$ ]] || { printf 'Use --initials with 2-4 uppercase letters\n' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf -v module_num '%02d' "$module"
shopt -s nullglob
module_dirs=("$repo_root"/student-track/module-"$module_num"-*)
(( ${#module_dirs[@]} == 1 )) || { printf 'Expected one student-track module for M%s, found %d\n' "$module_num" "${#module_dirs[@]}" >&2; exit 1; }
module_dir="${module_dirs[0]}"
module_name="$(basename "$module_dir")"
module_workspace="$workspace_root/$module_name"

if [[ -e "$module_workspace" ]]; then
  printf 'Workspace already exists: %s\nChoose --workspace-root with a new path.\n' "$module_workspace" >&2
  exit 1
fi
mkdir -p "$module_workspace"
if [[ -d "$module_dir/starter" ]]; then
  cp -R "$module_dir/starter/." "$module_workspace/"
fi
cat > "$module_workspace/.gitignore" <<'EOF'
*.tfstate
*.tfstate.*
*.tfplan
*.tfplan.*
.terraform/
.terraform.lock.hcl
*.tfvars
*.tfvars.json
.env
secrets/
*.p8
*.pem
*.key
*.pub
.student-workspace.json
EOF
cat > "$module_workspace/.student-workspace.json" <<EOF
{
  "module": "$module_num",
  "moduleName": "$module_name",
  "initials": "$initials",
  "workspaceRoot": "$module_workspace",
  "repoRoot": "$repo_root",
  "branch": "module-$module_num-$initials"
}
EOF
(
  cd "$module_workspace"
  git init --quiet
  git checkout -b "module-$module_num-$initials" --quiet
  git add .
  git -c user.name='Data2AI Learner' -c user.email='learner@local.invalid' commit -m "chore(m$module_num): scaffold workspace for $initials" --quiet
)
printf 'Workspace ready: %s\n' "$module_workspace"
printf 'Guide: %s/module.md\n' "$module_dir"
printf 'Validate: ./scripts/self-paced-lab.sh --module %d --all\n' "$module"
