# JSON Logic Benchmarks

Automated benchmarks measuring **performance** and **correctness** of JSON Logic implementations across multiple languages and runtime versions.

## Latest Results (Ruby)

| Gem | Version | Pass Rate | Ops/sec | Avg Time |
|-----|---------|-----------|---------|----------|
| json-logic-rb | 0.2.0 | **100.0%** | 263,618 | 3.79 μs |
| shiny_json_logic | 0.2.14 | 99.36% | 272,642 | 3.67 μs |
| json_logic | 0.4.7 | 71.12% | 426,261 | 2.35 μs |
| json_logic_ruby | 0.2.4 | 48.31% | 732,647 | 1.37 μs |

*Ruby 3.2.9 on arm64-darwin24 | 1,416 tests | [Full results →](benchmark_ruby/results/)*

## What We Measure

- **Correctness**: Pass rate against 1,416 tests from multiple sources
- **Performance**: Operations per second (only counting passed tests)
- **Cross-version**: Same tests across Ruby 2.7, 3.1, 3.2, 3.3, 3.4
- **Cross-platform**: Ubuntu and macOS

## Test Sources

Tests are aggregated from:

1. **[json-logic/.github](https://github.com/json-logic/.github/tree/main/tests)** - Official community test suites
2. **[json-logic/compat-tables](https://github.com/json-logic/compat-tables)** - Comprehensive compatibility tests covering edge cases

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

Results are written to `benchmark_ruby/results/ruby_<version>.json`.

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
│   └── results/                # JSON output files
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

## Contributing

1. **Add a gem**: Edit `performance_benchmark.rb` to include new implementations
2. **Add a language**: Create a new `benchmark_<lang>/` directory following the Ruby pattern
3. **Improve tests**: Submit test cases to [json-logic/.github](https://github.com/json-logic/.github) or [json-logic/compat-tables](https://github.com/json-logic/compat-tables)

## License

MIT
