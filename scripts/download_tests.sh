#!/bin/bash
#
# Download JSON Logic test suites from official sources
# This script is language-agnostic and used by all benchmark runners
#
# Usage: ./scripts/download_tests.sh
#
# Downloads to: tests/
#   - tests/official/    (from json-logic/.github)
#   - tests/compat/      (from json-logic/compat-tables)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$ROOT_DIR/tests"

# Clean and create directories
rm -rf "$TESTS_DIR"
mkdir -p "$TESTS_DIR/official"
mkdir -p "$TESTS_DIR/compat"

echo "Downloading JSON Logic test suites..."
echo

# ============================================================================
# 1. Download from json-logic/.github (official community tests)
# ============================================================================
echo "==> json-logic/.github (official)"

API_URL="https://api.github.com/repos/json-logic/.github/contents/tests"
RAW_BASE="https://raw.githubusercontent.com/json-logic/.github/main/tests"

# Fetch directory listing
ENTRIES=$(curl -s "$API_URL")

# Process each entry
echo "$ENTRIES" | jq -r '.[] | "\(.type) \(.name) \(.url)"' | while read -r type name url; do
  if [[ "$type" == "file" && "$name" == *.json ]]; then
    echo "    $name"
    curl -s "$RAW_BASE/$name" -o "$TESTS_DIR/official/$name"
  elif [[ "$type" == "dir" ]]; then
    echo "    $name/"
    mkdir -p "$TESTS_DIR/official/$name"
    
    # Fetch subdirectory
    SUBENTRIES=$(curl -s "$url")
    echo "$SUBENTRIES" | jq -r '.[] | select(.type == "file" and (.name | endswith(".json"))) | .name' | while read -r subname; do
      echo "      $subname"
      curl -s "$RAW_BASE/$name/$subname" -o "$TESTS_DIR/official/$name/$subname"
    done
  fi
done

echo

# ============================================================================
# 2. Download from json-logic/compat-tables
# ============================================================================
echo "==> json-logic/compat-tables"

INDEX_URL="https://raw.githubusercontent.com/json-logic/compat-tables/main/suites/index.json"
COMPAT_BASE="https://raw.githubusercontent.com/json-logic/compat-tables/main/suites"

# Fetch index
SUITE_FILES=$(curl -s "$INDEX_URL")

# Download each suite
echo "$SUITE_FILES" | jq -r '.[]' | while read -r suite_path; do
  echo "    $suite_path"
  
  # Create subdirectory if needed
  suite_dir=$(dirname "$suite_path")
  if [[ "$suite_dir" != "." ]]; then
    mkdir -p "$TESTS_DIR/compat/$suite_dir"
  fi
  
  curl -s "$COMPAT_BASE/$suite_path" -o "$TESTS_DIR/compat/$suite_path"
done

echo
echo "Done! Tests downloaded to: $TESTS_DIR"
echo

# Count tests
OFFICIAL_COUNT=$(find "$TESTS_DIR/official" -name "*.json" | wc -l | tr -d ' ')
COMPAT_COUNT=$(find "$TESTS_DIR/compat" -name "*.json" | wc -l | tr -d ' ')
echo "  Official suites: $OFFICIAL_COUNT"
echo "  Compat suites:   $COMPAT_COUNT"
echo "  Total:           $((OFFICIAL_COUNT + COMPAT_COUNT))"
