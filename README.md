# JSON Logic Benchmarks

Automated benchmarks measuring **performance** and **correctness** of JSON Logic implementations across multiple languages and runtime versions.

## What We Measure

- **Correctness**: Pass rate against official test suites
- **Performance**: Operations per second (only counting passed tests)
- **Cross-platform**: Ubuntu and macOS

## Test Source

Tests are downloaded from **[json-logic/.github](https://github.com/json-logic/.github/tree/main/tests)** - the official community test suites.

All tests use the standardized format defined in [TEST_FORMAT.md](https://github.com/json-logic/.github/blob/main/TEST_FORMAT.md).

## How It Works

```
Weekly (Sunday 00:00 UTC)
         │
         ▼
┌─────────────────────────────────────────┐
│         GitHub Actions Matrix           │
│  ┌───────────┐  ┌───────────────────┐   │
│  │ ubuntu    │  │ Ruby 2.7, 3.1,    │   │
│  │ macos     │  │ 3.2, 3.3, 3.4     │   │
│  └───────────┘  └───────────────────┘   │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  1. Download fresh test suites          │
│  2. Run each gem against all tests      │
│  3. Measure time only for passed tests  │
│  4. Output JSON results                 │
│  5. Commit results to repo              │
└─────────────────────────────────────────┘
```

## Running Locally

```bash
# 1. Download test suites (requires curl and jq)
./scripts/download_tests.sh

# 2. Run the benchmark
ruby benchmark_ruby/performance_benchmark.rb
```

Results are written to `benchmark_ruby/results/<date>/ruby_<version>_<os>.json`.

## Project Structure

```
jsonlogic_benchmarks/
├── .github/workflows/
│   └── ruby_benchmarks.yml     # CI: weekly + manual trigger
├── scripts/
│   └── download_tests.sh       # Shared test downloader (all languages)
├── tests/                      # Downloaded tests (gitignored)
├── benchmark_ruby/
│   ├── performance_benchmark.rb
│   └── results/
│       ├── 2026-02-21/         # Historical results by date
│       │   ├── ruby_3.2.10_linux.json
│       │   └── ruby_4.0.1_macos.json
│       └── latest/             # Most recent results (updated each run)
├── CONTRIBUTING.md             # Guide for adding new languages
└── README.md
```

## Result Format

```json
{
  "language": "ruby",
  "language_version": "3.2.9",
  "platform": "arm64-darwin24",
  "timestamp": "2026-02-20T16:21:21+01:00",
  "total_tests": 1416,
  "results": {
    "json-logic-rb": {
      "version": "0.2.0",
      "passed": 1416,
      "failed": 0,
      "pass_rate": 100.0,
      "ops_per_second": 263618.39
    }
  }
}
```

## Methodology

- **Timing**: Only passed tests contribute to timing measurements
- **Iterations**: Each test runs 10 iterations; average time is calculated
- **Error handling**: Tests expecting errors (format: `{"error": {"type": "..."}}`) are validated correctly
- **Consistency**: GitHub Actions runners provide consistent hardware across runs

## License

MIT
