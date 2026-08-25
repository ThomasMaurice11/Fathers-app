#!/usr/bin/env bash
# ============================================================
# Church Fathers App - local bootstrap script
#
# Run this ONCE from the project root:
#   bash scripts/setup.sh
#
# It does NOT create your Supabase project for you (that step
# needs your browser login), it just prepares your local
# environment so the supabase CLI commands in README.md work.
# ============================================================
set -e

echo "==> Checking for Node.js / npx..."
if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found. Install Node.js 18+ first: https://nodejs.org"
  exit 1
fi

echo "==> Checking Supabase CLI (via npx, no global install needed)..."
npx supabase --version

if [ ! -f ".env" ]; then
  echo "==> Creating .env from .env.example"
  cp .env.example .env
  echo "    -> Fill in .env with your project URL + anon key after 'supabase link'."
else
  echo "==> .env already exists, skipping."
fi

echo "==> Done. Next steps:"
echo "  1) npx supabase login"
echo "  2) npx supabase link --project-ref <your-project-ref>"
echo "  3) npx supabase db push"
echo "  4) npx supabase functions deploy"
echo ""
echo "See README.md for the full command reference."
