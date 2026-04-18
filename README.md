# JSON Logic Benchmarks

Automated benchmarks measuring **performance** and **correctness** of JSON Logic implementations across multiple languages and runtime versions.

## What We Measure

- **Correctness**: Pass rate against the official test suite (613 tests from [json-logic/.github](https://github.com/json-logic/.github/tree/main/tests))
- **Performance**: Operations per second (only counting passed tests)
- **Cross-platform**: Ubuntu and macOS

## Languages

| Language    | Libraries | Versions |
|-------------|-----------|----------|
| **Ruby**    | `shiny_json_logic`, `json-logic-rb`, `json_logic`, `json_logic_ruby` | 2.7, 3.1, 3.2, 3.3, 3.4, 4.0 |
| **PHP**     | `shiny/json-logic-php`, `jwadhams/json-logic-php` | 8.1, 8.2, 8.3 |
| **Crystal** | `shiny_json_logic` | 1.14, latest |

## Test Source

Tests are downloaded from **[json-logic/.github](https://github.com/json-logic/.github/tree/main/tests)** — the official community test suites.

All tests use the standardized format defined in [TEST_FORMAT.md](https://github.com/json-logic/.github/blob/main/TEST_FORMAT.md).

## How It Works

```
Weekly (Sunday 00:00 UTC)
         │
         ▼
┌──────────────────────────────────────────────┐
│           GitHub Actions Matrix              │
│  ┌───────────┐  ┌────────────────────────┐   │
│  │ ubuntu    │  │ Ruby 2.7–4.0 (±YJIT)   │   │
│  │ macos     │  │ PHP  8.1–8.3           │   │
│  └───────────┘  │ Crystal 1.14, latest   │   │
│                 └────────────────────────┘   │
└──────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  1. Download fresh test suites               │
│  2. Run each library against all tests       │
│  3. Measure time only for passed tests       │
│  4. Output JSON results                      │
│  5. Commit results to repo                   │
└──────────────────────────────────────────────┘
```

## Running Locally

### Ruby

```bash
# 1. Download test suites (requires curl and jq)
./scripts/download_tests.sh

# 2. Run the benchmark
ruby benchmark_ruby/performance_benchmark.rb
```

Results are written to `benchmark_ruby/results/<date>/ruby_<version>_<os>.json`.

### PHP

```bash
# 1. Download test suites (requires curl and jq)
./scripts/download_tests.sh

# 2. Install dependencies
cd benchmark_php && composer install && cd ..

# 3. Run the benchmark
php benchmark_php/performance_benchmark.php            # stdclass mode (default, full spec compliance)
php benchmark_php/performance_benchmark.php --arrays   # arrays mode (json_decode with assoc flag)
```

Results are written to `benchmark_php/results/<date>/php_<version>_<os>_<stdclass|arrays>.json`.

### Crystal

```bash
# 1. Download test suites (requires curl and jq)
./scripts/download_tests.sh

# 2. Install shards
cd benchmark_crystal && shards install && cd ..

# 3. Build and run
cd benchmark_crystal
crystal build performance_benchmark.cr -o performance_benchmark --release
./performance_benchmark
```

Results are written to `benchmark_crystal/results/<date>/crystal_<version>_<os>.json`.

## Project Structure

```
jsonlogic_benchmarks/
├── .github/workflows/
│   ├── ruby_benchmarks.yml     # CI: weekly + manual trigger (Ruby)
│   ├── php_benchmarks.yml      # CI: weekly + manual trigger (PHP)
│   └── crystal_benchmarks.yml  # CI: weekly + manual trigger (Crystal)
├── scripts/
│   └── download_tests.sh       # Shared test downloader (all languages)
├── tests/                      # Downloaded tests (gitignored)
├── benchmark_ruby/
│   ├── performance_benchmark.rb
│   ├── benchmark_runner.rb
│   └── results/
│       ├── 2026-02-21/         # Historical results by date
│       │   ├── ruby_3.2.10_linux.json
│       │   └── ruby_4.0.1_macos.json
│       └── latest/             # Most recent results (updated each run)
├── benchmark_php/
│   ├── performance_benchmark.php
│   ├── benchmark_runner.php
│   ├── composer.json
│   └── results/
│       └── latest/
├── benchmark_crystal/
│   ├── performance_benchmark.cr
│   ├── shard.yml
│   └── results/
│       └── latest/
├── CONTRIBUTING.md             # Guide for adding new languages
└── README.md
```

## Result Format

```json
{
  "language": "ruby",
  "language_version": "3.2.9",
  "platform": "arm64-darwin24",
  "os": "macos",
  "timestamp": "2026-02-20T16:21:21+01:00",
  "total_tests": 613,
  "results": {
    "shiny_json_logic": {
      "version": "0.3.6",
      "passed": 601,
      "failed": 0,
      "pass_rate": 100.0,
      "ops_per_second": 67523.0,
      "peak_memory_mb": 42.1
    }
  },
  "comparable_results": { }
}
```

## Methodology

- **Timing**: Only passed tests contribute to timing measurements
- **Iterations**: 10 warmup + 10 benchmark iterations per run; ops/sec is calculated over the total
- **Two modes**:
  - **Mode 1** — each library measured against its own passing tests (shows correctness + peak performance)
  - **Mode 2** — all libraries measured on the intersection of tests they all pass (apples-to-apples comparison)
- **PHP decode modes**: benchmarks run twice per PHP version — `stdclass` (`json_decode` without assoc flag, full spec compliance) and `arrays` (`json_decode` with assoc flag). stdclass is the canonical mode; arrays mode documents the 1-test gap caused by `{}` / `[]` being indistinguishable in PHP associative arrays.
- **Error handling**: Tests expecting errors (`{"error": {"type": "..."}}`) pass only if the library raises; fail if it returns a value
- **Consistency**: GitHub Actions runners provide consistent hardware across runs

## License

MIT
