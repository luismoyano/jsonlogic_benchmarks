#!/bin/bash
#
# Download JSON Logic test suites from official source
# This script is language-agnostic and used by all benchmark runners
#
# Usage: ./scripts/download_tests.sh
#
# Downloads to: tests/
#   - tests/    (from json-logic/.github - official community tests)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$ROOT_DIR/tests"

# Clean and create directory
rm -rf "$TESTS_DIR"
mkdir -p "$TESTS_DIR"

echo "Downloading JSON Logic test suites..."
echo

# ============================================================================
# Download from json-logic/.github (official community tests)
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
    curl -s "$RAW_BASE/$name" -o "$TESTS_DIR/$name"
  elif [[ "$type" == "dir" ]]; then
    echo "    $name/"
    mkdir -p "$TESTS_DIR/$name"
    
    # Fetch subdirectory
    SUBENTRIES=$(curl -s "$url")
    echo "$SUBENTRIES" | jq -r '.[] | select(.type == "file" and (.name | endswith(".json"))) | .name' | while read -r subname; do
      echo "      $subname"
      curl -s "$RAW_BASE/$name/$subname" -o "$TESTS_DIR/$name/$subname"
    done
  fi
done

echo
echo "Done! Tests downloaded to: $TESTS_DIR"
echo

# Count tests
TEST_COUNT=$(find "$TESTS_DIR" -name "*.json" | wc -l | tr -d ' ')
echo "  Test suites: $TEST_COUNT"
