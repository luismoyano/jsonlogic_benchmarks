#!/usr/bin/env php
<?php

/**
 * JSON Logic PHP Implementations - Performance & Compatibility Benchmark
 * ========================================================================
 *
 * Reads test suites from ../tests/ (downloaded by scripts/download_tests.sh)
 *
 * Measures:
 *   - Correctness: passed/failed tests
 *   - Performance: time only for passed tests
 *   - Compatibility: percentage of tests passed
 *
 * Libraries tested:
 *   - shiny/json-logic-php  (https://packagist.org/packages/shiny/json-logic-php)
 *   - jwadhams/json-logic-php (https://packagist.org/packages/jwadhams/json-logic-php)
 *
 * Usage:
 *   php performance_benchmark.php [--arrays] [--date YYYY-MM-DD] [--lib-version NAME=VERSION]
 *
 * Decode modes:
 *   (default)  stdclass — json_decode without true flag (full spec compliance)
 *   --arrays   arrays   — json_decode with true flag    (associative arrays)
 */

$SCRIPT_DIR = __DIR__;
$ROOT_DIR   = dirname($SCRIPT_DIR);
$TESTS_DIR  = $ROOT_DIR . '/tests';

// Parse CLI flags
$args = array_slice($argv, 1);

$OVERRIDE_DATE = null;
$LIB_VERSION_OVERRIDES = [];
$DECODE_MODE = 'stdclass'; // default

for ($i = 0; $i < count($args); $i++) {
    if ($args[$i] === '--date' && isset($args[$i + 1])) {
        $OVERRIDE_DATE = $args[++$i];
    } elseif ($args[$i] === '--lib-version' && isset($args[$i + 1])) {
        [$name, $ver] = explode('=', $args[++$i], 2);
        $LIB_VERSION_OVERRIDES[$name] = $ver;
    } elseif ($args[$i] === '--arrays') {
        $DECODE_MODE = 'arrays';
    }
}

const WARMUP_ITERATIONS    = 10;
const BENCHMARK_ITERATIONS = 10;

// Libraries to benchmark
const LIBS = [
    'shiny/json-logic-php' => [
        'package'  => 'shiny/json-logic-php',
        'adapter'  => 'shiny',
        'min_php'  => '8.1',
    ],
    'jwadhams/json-logic-php' => [
        'package'  => 'jwadhams/json-logic-php',
        'adapter'  => 'jwadhams',
        'min_php'  => '7.0',
    ],
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function php_version_string(): string
{
    return PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION . '.' . PHP_RELEASE_VERSION;
}

function format_number(int $n): string
{
    return number_format($n);
}

function load_test_suites(string $tests_dir): array
{
    if (!is_dir($tests_dir)) {
        fwrite(STDERR, "ERROR: Tests directory not found: $tests_dir\n");
        fwrite(STDERR, "Run scripts/download_tests.sh first\n");
        exit(1);
    }

    echo "Loading test suites from $tests_dir...\n";

    $all_tests = [];

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($tests_dir, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($iterator as $file) {
        if ($file->getExtension() !== 'json') {
            continue;
        }

        $relative_path = ltrim(str_replace($tests_dir, '', $file->getPathname()), '/');
        $suite_name    = str_replace(['/', '\\'], '_', preg_replace('/\.json$/', '', $relative_path));

        $file_content = file_get_contents($file->getPathname());
        $raw = json_decode($file_content, true);
        if (!is_array($raw)) {
            echo "  $relative_path: PARSE ERROR\n";
            continue;
        }

        // Re-parse the file as stdclass so we can json_encode each field back
        // to a canonical JSON string that preserves {} vs [].
        $raw_std = json_decode($file_content);

        // Filter out comment strings (top-level strings in the array), keep
        // only test objects. We use the assoc version to detect structure and
        // the stdclass version to extract per-field JSON strings.
        $tests = [];
        foreach ($raw as $idx => $item) {
            if (!is_array($item) || !array_is_assoc($item)) {
                continue;
            }
            $item_std = $raw_std[$idx];
            $tests[] = [
                'rule_json'   => isset($item['rule'])   ? json_encode($item_std->rule)   : 'null',
                'data_json'   => isset($item['data'])   ? json_encode($item_std->data)   : 'null',
                'result_json' => isset($item['result']) ? json_encode($item_std->result) : 'null',
                'error'       => $item['error'] ?? null,
            ];
        }

        if (count($tests) > 0) {
            $all_tests[$suite_name] = $tests;
            echo "  $relative_path: " . count($tests) . " tests\n";
        }
    }

    return $all_tests;
}

function array_is_assoc(array $arr): bool
{
    if (empty($arr)) {
        return true;
    }
    return array_keys($arr) !== range(0, count($arr) - 1);
}

function flatten_tests(array $all_tests): array
{
    $flattened = [];
    foreach ($all_tests as $tests) {
        foreach ($tests as $test) {
            $flattened[] = [
                'rule_json'   => $test['rule_json']   ?? 'null',
                'data_json'   => $test['data_json']   ?? 'null',
                'result_json' => $test['result_json'] ?? 'null',
                'error'       => $test['error']       ?? null,
            ];
        }
    }
    return $flattened;
}

function results_equal(mixed $actual, mixed $expected): bool
{
    if (is_float($expected) && is_float($actual)) {
        return abs($actual - $expected) < 0.0001;
    }
    if (is_float($expected) && is_int($actual)) {
        return abs((float)$actual - $expected) < 0.0001;
    }
    if (is_float($actual) && is_int($expected)) {
        return abs($actual - (float)$expected) < 0.0001;
    }
    if (is_array($expected) && is_array($actual)) {
        if (count($expected) !== count($actual)) {
            return false;
        }
        foreach ($expected as $k => $v) {
            if (!array_key_exists($k, $actual)) {
                return false;
            }
            if (!results_equal($actual[$k], $v)) {
                return false;
            }
        }
        return true;
    }
    // stdClass objects: compare structurally (two stdClass, or stdClass vs assoc array)
    $exp_is_obj = $expected instanceof \stdClass;
    $act_is_obj = $actual instanceof \stdClass;
    if ($exp_is_obj || $act_is_obj) {
        $exp_arr = $exp_is_obj ? (array)$expected : $expected;
        $act_arr = $act_is_obj ? (array)$actual   : $actual;
        if (!is_array($exp_arr) || !is_array($act_arr)) {
            return false;
        }
        if (count($exp_arr) !== count($act_arr)) {
            return false;
        }
        foreach ($exp_arr as $k => $v) {
            if (!array_key_exists($k, $act_arr)) {
                return false;
            }
            if (!results_equal($act_arr[$k], $v)) {
                return false;
            }
        }
        return true;
    }
    return $actual === $expected;
}

function memory_kb(): int
{
    return (int)(memory_get_usage(true) / 1024);
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

function run_benchmark(
    string $lib_name,
    array  $lib_config,
    array  $all_tests,
    array  $subset_indices = [],
    bool   $report_passed_indices = false,
    string $lib_version_override = '',
    string $decode_mode = 'stdclass'
): array {
    $current_php = php_version_string();
    $min_php     = $lib_config['min_php'];

    if (version_compare($current_php, $min_php, '<')) {
        return [
            'status' => 'incompatible',
            'error'  => "Requires PHP >= $min_php",
        ];
    }

    $config = [
        'package'               => $lib_config['package'],
        'adapter'               => $lib_config['adapter'],
        'tests'                 => count($subset_indices) > 0
            ? array_values(array_map(fn($i) => flatten_tests($all_tests)[$i], $subset_indices))
            : flatten_tests($all_tests),
        'warmup_iterations'     => WARMUP_ITERATIONS,
        'benchmark_iterations'  => BENCHMARK_ITERATIONS,
        'report_passed_indices' => $report_passed_indices,
        'decode_mode'           => $decode_mode,
    ];
    if ($lib_version_override !== '') {
        $config['lib_version'] = $lib_version_override;
    }

    $runner_script = __DIR__ . '/benchmark_runner.php';
    $config_json   = base64_encode(json_encode($config));
    $cmd           = "php " . escapeshellarg($runner_script) . " " . escapeshellarg($config_json) . " 2>/dev/null";

    $output = [];
    $exit_code = 0;
    exec($cmd, $output, $exit_code);

    $output_str = implode("\n", $output);

    if (str_contains($output_str, 'BENCHMARK_RESULT:')) {
        $json_str = trim(explode('BENCHMARK_RESULT:', $output_str, 2)[1]);
        $decoded  = json_decode($json_str, true);
        if (json_last_error() === JSON_ERROR_NONE) {
            return $decoded;
        }
        return ['status' => 'error', 'error' => 'Invalid JSON: ' . substr($json_str, 0, 100)];
    }

    return ['status' => 'error', 'error' => 'No benchmark result found'];
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

function print_results_table(array $results): void
{
    uasort($results, function ($a, $b) {
        if ($a['status'] !== 'success' && $b['status'] !== 'success') {
            return 0;
        }
        if ($a['status'] !== 'success') {
            return 1;
        }
        if ($b['status'] !== 'success') {
            return -1;
        }
        if (($b['pass_rate'] ?? 0) !== ($a['pass_rate'] ?? 0)) {
            return ($b['pass_rate'] ?? 0) <=> ($a['pass_rate'] ?? 0);
        }
        return ($b['ops_per_second'] ?? 0) <=> ($a['ops_per_second'] ?? 0);
    });

    echo "| Library                      | Version | Pass Rate | Passed | Failed | Ops/sec     | Peak Mem  |\n";
    echo "|------------------------------|---------|-----------|--------|--------|-------------|-----------|";
    echo "\n";

    foreach ($results as $lib_name => $result) {
        $name = str_pad($lib_name, 28);
        switch ($result['status']) {
            case 'incompatible':
                echo "| $name | -       | INCOMPATIBLE - {$result['error']}";
                echo "\n";
                break;
            case 'error':
                $err = substr($result['error'], 0, 50);
                echo "| $name | -       | ERROR - $err";
                echo "\n";
                break;
            default:
                $version  = str_pad(substr($result['version'] ?? 'unknown', 0, 7), 7);
                $rate     = str_pad(($result['pass_rate'] ?? 0) . '%', 9, ' ', STR_PAD_LEFT);
                $passed   = str_pad((string)($result['passed'] ?? 0), 6, ' ', STR_PAD_LEFT);
                $failed   = str_pad((string)($result['failed'] ?? 0), 6, ' ', STR_PAD_LEFT);
                $ops      = str_pad(format_number((int)($result['ops_per_second'] ?? 0)), 11, ' ', STR_PAD_LEFT);
                $peak_mem = str_pad(($result['peak_memory_mb'] ?? 0) . ' MB', 9, ' ', STR_PAD_LEFT);
                echo "| $name | $version | $rate | $passed | $failed | $ops | $peak_mem |\n";
        }
    }
}

function print_comparable_results_table(array $results, int $common_count): void
{
    uasort($results, function ($a, $b) {
        if ($a['status'] !== 'success') {
            return 1;
        }
        if ($b['status'] !== 'success') {
            return -1;
        }
        return ($b['ops_per_second'] ?? 0) <=> ($a['ops_per_second'] ?? 0);
    });

    echo "| Library                      | Version | Ops/sec ($common_count common tests) |\n";
    echo "|------------------------------|---------|-------------------------------|";
    echo "\n";

    foreach ($results as $lib_name => $result) {
        $name = str_pad($lib_name, 28);
        switch ($result['status']) {
            case 'incompatible':
                echo "| $name | -       | INCOMPATIBLE                  |\n";
                break;
            case 'error':
                echo "| $name | -       | ERROR                         |\n";
                break;
            default:
                $version = str_pad(substr($result['version'] ?? 'unknown', 0, 7), 7);
                $ops     = str_pad(format_number((int)($result['ops_per_second'] ?? 0)), 29, ' ', STR_PAD_LEFT);
                echo "| $name | $version | $ops |\n";
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(string $tests_dir, ?string $override_date, array $lib_version_overrides, string $decode_mode): void
{
    echo str_repeat('=', 70) . "\n";
    echo "RESULTS SUMMARY - Mode 1 ($decode_mode, own passing tests)\n";
    echo str_repeat('=', 70) . "\n\n";

    echo "PHP version: " . php_version_string() . "\n";
    echo "PHP platform: " . PHP_OS . "\n";
    echo "Decode mode: $decode_mode\n";
    if ($override_date) {
        echo "Date override: $override_date\n";
    }
    if (!empty($lib_version_overrides)) {
        echo "Library version overrides: " . json_encode($lib_version_overrides) . "\n";
    }
    echo "Warmup iterations: " . WARMUP_ITERATIONS . "\n";
    echo "Benchmark iterations: " . BENCHMARK_ITERATIONS . "\n\n";

    $all_tests       = load_test_suites($tests_dir);
    $total_test_count = array_sum(array_map('count', $all_tests));

    echo "\nLoaded " . count($all_tests) . " test suites with $total_test_count total tests\n\n";

    // -----------------------------------------------------------------------
    // MODE 1: Each library measured on its own passing tests
    // -----------------------------------------------------------------------
    echo "--- Mode 1 ($decode_mode): Each library measured on its own passing tests ---\n\n";

    $results = [];

    foreach (LIBS as $lib_name => $lib_config) {
        echo "Benchmarking $lib_name... ";
        flush();

        $result = run_benchmark(
            $lib_name,
            $lib_config,
            $all_tests,
            [],
            true,
            $lib_version_overrides[$lib_name] ?? '',
            $decode_mode
        );
        $results[$lib_name] = $result;

        switch ($result['status']) {
            case 'incompatible':
                echo "SKIP ({$result['error']})\n";
                break;
            case 'error':
                echo "ERROR (" . substr($result['error'], 0, 50) . ")\n";
                break;
            default:
                $rate     = $result['pass_rate'] ?? 0;
                $ops      = format_number((int)($result['ops_per_second'] ?? 0));
                $peak_mem = $result['peak_memory_mb'] ?? 0;
                echo "{$rate}% pass, {$ops} ops/sec, {$peak_mem} MB peak\n";
        }
    }

    echo "\n" . str_repeat('=', 70) . "\n";
    echo "RESULTS SUMMARY - Mode 1 (own passing tests)\n";
    echo str_repeat('=', 70) . "\n\n";

    print_results_table($results);

    echo "\nLegend:\n";
    echo "  Pass Rate = percentage of tests passed\n";
    echo "  Ops/sec   = operations per second (passed tests only)\n";
    echo "  Peak Mem  = peak memory usage during benchmark\n\n";

    // -----------------------------------------------------------------------
    // MODE 2: Intersection of passed tests
    // -----------------------------------------------------------------------
    echo "--- Mode 2 ($decode_mode): All libraries measured on common passing tests (intersection) ---\n\n";

    $per_lib_indices = [];
    foreach ($results as $lib_name => $result) {
        if ($result['status'] === 'success' && !empty($result['passed_indices'])) {
            $per_lib_indices[$lib_name] = array_map('intval', $result['passed_indices']);
        }
    }

    $comparable_results = [];

    if (count($per_lib_indices) < 2) {
        echo "Not enough compatible libraries to compute intersection.\n";
    } else {
        $intersection = array_values(array_reduce(
            $per_lib_indices,
            fn($carry, $item) => $carry === null ? $item : array_values(array_intersect($carry, $item)),
            null
        ));

        echo "Intersection: " . count($intersection) . " tests pass in ALL compatible libraries\n\n";

        foreach (LIBS as $lib_name => $lib_config) {
            if (($results[$lib_name]['status'] ?? '') !== 'success') {
                $comparable_results[$lib_name] = $results[$lib_name];
                continue;
            }

            echo "Benchmarking $lib_name (" . count($intersection) . " common tests)... ";
            flush();

            $result = run_benchmark(
                $lib_name,
                $lib_config,
                $all_tests,
                $intersection,
                false,
                $lib_version_overrides[$lib_name] ?? '',
                $decode_mode
            );
            $result['version'] ??= $results[$lib_name]['version'] ?? 'unknown';
            $comparable_results[$lib_name] = $result;

            switch ($result['status']) {
                case 'error':
                    echo "ERROR (" . substr($result['error'], 0, 50) . ")\n";
                    break;
                default:
                    echo format_number((int)($result['ops_per_second'] ?? 0)) . " ops/sec\n";
            }
        }

        echo "\n" . str_repeat('=', 70) . "\n";
        echo "RESULTS SUMMARY - Mode 2 ($decode_mode, " . count($intersection) . " common tests)\n";
        echo str_repeat('=', 70) . "\n\n";

        print_comparable_results_table($comparable_results, count($intersection));

        echo "\nLegend:\n";
        echo "  Common tests = " . count($intersection) . " tests that ALL compatible libraries pass\n";
        echo "  Ops/sec      = operations per second on the common subset\n\n";
    }

    // -----------------------------------------------------------------------
    // Save JSON
    // -----------------------------------------------------------------------
    $os_name = match (true) {
        str_contains(PHP_OS, 'Darwin') => 'macos',
        str_contains(PHP_OS, 'Linux')  => 'linux',
        str_contains(PHP_OS, 'WIN')    => 'windows',
        default                        => 'unknown',
    };

    $timestamp  = date('c');
    $json_output = [
        'language'           => 'php',
        'language_version'   => php_version_string(),
        'platform'           => PHP_OS,
        'os'                 => $os_name,
        'decode_mode'        => $decode_mode,
        'timestamp'          => $timestamp,
        'total_tests'        => $total_test_count,
        'results'            => $results,
        'comparable_results' => $comparable_results,
    ];

    $date_str         = $override_date ?? date('Y-m-d');
    $dated_results_dir = __DIR__ . "/results/$date_str";
    if (!is_dir($dated_results_dir)) {
        mkdir($dated_results_dir, 0755, true);
    }

    $filename    = "php_" . php_version_string() . "_" . $os_name . "_" . $decode_mode . ".json";
    $output_file = "$dated_results_dir/$filename";
    file_put_contents($output_file, json_encode($json_output, JSON_PRETTY_PRINT));
    echo "Results saved to: $output_file\n";
}

main($TESTS_DIR, $OVERRIDE_DATE, $LIB_VERSION_OVERRIDES, $DECODE_MODE);
