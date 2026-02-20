# Contributing a New Language

This guide explains how to add benchmarks for a new programming language.

## Directory Structure

```
jsonlogic_benchmarks/
├── scripts/
│   └── download_tests.sh      # Shared: downloads all test suites
├── tests/                      # Shared: downloaded tests (gitignored)
├── benchmark_ruby/            # Ruby implementation
├── benchmark_python/          # Python implementation (example)
├── benchmark_javascript/      # JavaScript implementation (example)
└── .github/workflows/
    ├── ruby_benchmarks.yml
    └── python_benchmarks.yml  # One workflow per language
```

## Steps to Add a New Language

### 1. Create benchmark directory

```bash
mkdir benchmark_<language>
mkdir benchmark_<language>/results
```

### 2. Create the benchmark script

Your script should:

1. **Read tests from `../tests/`** (downloaded by `scripts/download_tests.sh`)
2. **Run each test** against each implementation
3. **Measure time only for passed tests**
4. **Output JSON** to `results/<language>_<version>.json`

### 3. Create GitHub Actions workflow

Create `.github/workflows/<language>_benchmarks.yml` following the Ruby example.

## Test Format

All tests use the format defined in [TEST_FORMAT.md](https://github.com/json-logic/.github/blob/main/TEST_FORMAT.md):

```json
{
  "description": "Human-readable test description",
  "rule": { "+": [1, 2] },
  "data": {},
  "result": 3
}
```

Or for tests expecting errors:

```json
{
  "description": "Division by zero",
  "rule": { "/": [1, 0] },
  "data": {},
  "error": { "type": "DivisionByZero" }
}
```

**Note:** Arrays in test files may contain comment strings (not objects). Filter these out:
```ruby
tests = raw.select { |item| item.is_a?(Hash) }
```

## Output Format (Required)

All benchmark runners **must** output JSON in this exact format:

```json
{
  "language": "ruby",
  "language_version": "3.2.9",
  "platform": "x86_64-linux",
  "timestamp": "2026-02-20T16:21:21+00:00",
  "total_tests": 1200,
  "results": {
    "implementation_name": {
      "version": "1.2.3",
      "status": "success",
      "total_tests": 1200,
      "passed": 1180,
      "failed": 20,
      "pass_rate": 98.33,
      "avg_time_us": 3.5,
      "ops_per_second": 285714.29
    },
    "another_implementation": {
      "version": "2.0.0",
      "status": "success",
      ...
    }
  }
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `language` | string | Language name (lowercase) |
| `language_version` | string | Runtime version |
| `platform` | string | OS/architecture |
| `timestamp` | string | ISO 8601 timestamp |
| `total_tests` | integer | Total number of tests run |
| `results` | object | Map of implementation name → results |

### Per-Implementation Results

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Library/gem/package version |
| `status` | string | `"success"`, `"error"`, or `"incompatible"` |
| `total_tests` | integer | Tests attempted |
| `passed` | integer | Tests passed |
| `failed` | integer | Tests failed |
| `pass_rate` | float | Percentage (0-100) |
| `avg_time_us` | float | Average time per passed test (microseconds) |
| `ops_per_second` | float | Operations per second (passed tests only) |

### Error/Incompatible Status

When an implementation fails or is incompatible:

```json
{
  "status": "error",
  "error": "Could not install dependency"
}
```

```json
{
  "status": "incompatible",
  "error": "Requires Python >= 3.8",
  "min_version": "3.8"
}
```

## Timing Methodology

1. **Warmup**: Run all tests 2 times without timing
2. **Benchmark**: Run all tests 5 times with timing
3. **Only time passed tests**: Failed tests don't contribute to timing
4. **Use monotonic clock**: Avoid wall-clock drift

## Error Handling

For tests expecting errors (`"error": {...}`):

1. If the implementation **throws an error** → **PASS** (expected behavior)
2. If the implementation **returns a result** → **FAIL** (should have thrown)

For regular tests (`"result": ...`):

1. If the implementation **returns matching result** → **PASS**
2. If the implementation **throws an error** → **FAIL**
3. If the implementation **returns wrong result** → **FAIL**

## Result Comparison

Use deep equality with tolerance for floats:

```python
def results_equal(actual, expected):
    if isinstance(expected, float) and isinstance(actual, float):
        return abs(actual - expected) < 0.0001
    elif isinstance(expected, list) and isinstance(actual, list):
        return len(expected) == len(actual) and all(
            results_equal(a, e) for a, e in zip(actual, expected)
        )
    elif isinstance(expected, dict) and isinstance(actual, dict):
        return expected.keys() == actual.keys() and all(
            results_equal(actual[k], expected[k]) for k in expected
        )
    else:
        return actual == expected
```

## Example Workflow

```yaml
name: Python Benchmarks

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sundays
  workflow_dispatch:

jobs:
  benchmark:
    runs-on: ${{ matrix.os }}
    
    strategy:
      fail-fast: false
      max-parallel: 1
      matrix:
        os: [ubuntu-latest, macos-latest]
        python-version: ['3.8', '3.9', '3.10', '3.11', '3.12']

    steps:
      - uses: actions/checkout@v4
      
      - name: Download test suites
        run: ./scripts/download_tests.sh
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      
      - name: Run benchmark
        run: python benchmark_python/benchmark.py
      
      - name: Commit results
        run: |
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git config user.name "github-actions[bot]"
          git pull --rebase
          git add benchmark_python/results/
          git diff --staged --quiet || git commit -m "benchmark: ${{ matrix.os }} python-${{ matrix.python-version }}"
          git push
```

## Questions?

Open an issue or check the Ruby implementation in `benchmark_ruby/` as a reference.
