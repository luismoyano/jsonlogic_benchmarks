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

# Use GitHub token if available (avoids rate limiting)
AUTH_HEADER=""
if [[ -n "$GITHUB_TOKEN" ]]; then
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
  echo "Using GitHub token for API requests"
fi

# Helper function for API requests
api_get() {
  if [[ -n "$AUTH_HEADER" ]]; then
    curl -s -H "$AUTH_HEADER" "$1"
  else
    curl -s "$1"
  fi
}

# Fetch directory listing
ENTRIES=$(api_get "$API_URL")

# Check if response is valid JSON array
if ! echo "$ENTRIES" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "ERROR: GitHub API returned unexpected response (rate limit?):"
  echo "$ENTRIES" | head -5
  echo
  echo "Tip: Set GITHUB_TOKEN environment variable to avoid rate limiting"
  exit 1
fi

# Process each entry
echo "$ENTRIES" | jq -r '.[] | "\(.type) \(.name) \(.url)"' | while read -r type name url; do
  if [[ "$type" == "file" && "$name" == *.json ]]; then
    echo "    $name"
    curl -s "$RAW_BASE/$name" -o "$TESTS_DIR/$name"
  elif [[ "$type" == "dir" ]]; then
    echo "    $name/"
    mkdir -p "$TESTS_DIR/$name"
    
    # Fetch subdirectory
    SUBENTRIES=$(api_get "$url")
    
    # Check if subdirectory response is valid
    if ! echo "$SUBENTRIES" | jq -e 'type == "array"' > /dev/null 2>&1; then
      echo "      WARNING: Could not fetch $name/ (rate limit?)"
      continue
    fi
    
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

if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "ERROR: No tests downloaded!"
  exit 1
fi
