#!/usr/bin/env bash
# Post-clone setup for Lean Security template projects.
# Run once after cloning.
#
# Usage:
#   git clone <template-repo> my-project
#   cd my-project
#   ./setup.sh

set -euo pipefail

# Create .git/info/exclude for local-only ignores
# These patterns are ignored locally but never committed to .gitignore,
# so they don't affect collaborators or downstream repos.
mkdir -p .git/info
cat > .git/info/exclude << 'EOF'
# Local-only ignores — not shared via .gitignore
# See: https://git-scm.com/docs/gitignore

# Claude Code directory — committed in template, local-only in projects
.claude/

# Personal Claude Code overrides
CLAUDE.local.md

# Local notes and scratch files
scratch/
notes/
*.local.*
EOF

echo "✓ .git/info/exclude created"

# Install dependencies and pre-commit hooks
if command -v poetry &> /dev/null; then
  poetry install --with dev
  poetry run pre-commit install
  echo "✓ Dependencies installed"
  echo "✓ Pre-commit hooks installed"
else
  echo "⚠ Poetry not found. Run 'poetry install --with dev && poetry run pre-commit install' manually."
fi

echo "✓ Template ready. Run /project:new-project in Claude Code to initialize."
