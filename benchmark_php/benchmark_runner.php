#!/usr/bin/env php
<?php

/**
 * benchmark_runner.php — isolated per-library benchmark subprocess
 * =================================================================
 *
 * Invoked by performance_benchmark.php as a subprocess.
 * Receives a base64-encoded JSON config via ARGV[1].
 *
 * Config keys:
 *   package               - Composer package name (e.g. 'shiny/json-logic-php')
 *   adapter               - which call adapter to use ('shiny' or 'jwadhams')
 *   tests                 - array of {rule, data, result, error} objects
 *   warmup_iterations     - int
 *   benchmark_iterations  - int
 *   report_passed_indices - bool
 *   decode_mode           - 'stdclass' (default) or 'arrays'
 *   lib_version           - (optional) version string override
 */

$config = json_decode(base64_decode($argv[1]), true);
if (!$config) {
    echo 'BENCHMARK_RESULT:' . json_encode(['status' => 'error', 'error' => 'Invalid config']);
    exit(0);
}

$adapter              = $config['adapter'];
$package              = $config['package'];
$tests                = $config['tests'];
$warmup_iterations    = $config['warmup_iterations'];
$bench_iterations     = $config['benchmark_iterations'];
$report_indices       = $config['report_passed_indices'] ?? false;
$decode_mode          = $config['decode_mode'] ?? 'stdclass';

// Tests arrive with rule_json/data_json/result_json as raw JSON strings.
// Decode them with the chosen mode so {} is preserved as stdClass in stdclass
// mode, or becomes [] in arrays mode.
$use_assoc = ($decode_mode === 'arrays');
foreach ($tests as &$test) {
    $test['rule']   = json_decode($test['rule_json']   ?? 'null', $use_assoc);
    $test['data']   = json_decode($test['data_json']   ?? 'null', $use_assoc);
    $test['result'] = json_decode($test['result_json'] ?? 'null', $use_assoc);
}
unset($test);

// Resolve vendor autoload relative to this script's repo root
$vendor_autoload = __DIR__ . '/vendor/autoload.php';
if (!file_exists($vendor_autoload)) {
    echo 'BENCHMARK_RESULT:' . json_encode([
        'status' => 'error',
        'error'  => "vendor/autoload.php not found — run composer install in benchmark_php/",
    ]);
    exit(0);
}

require_once $vendor_autoload;

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

function call_adapter(string $adapter, mixed $logic, mixed $data): mixed
{
    return match ($adapter) {
        'shiny'    => \ShinyJsonLogic\ShinyJsonLogic::apply($logic, $data),
        'jwadhams' => \JWadhams\JsonLogic::apply($logic, $data),
        default    => throw new \InvalidArgumentException("Unknown adapter: $adapter"),
    };
}

function get_version(string $adapter): string
{
    try {
        $installed = json_decode(
            file_get_contents(__DIR__ . '/vendor/composer/installed.json'),
            true
        );
        $packages = $installed['packages'] ?? $installed;
        $name = match ($adapter) {
            'shiny'    => 'shiny/json-logic-php',
            'jwadhams' => 'jwadhams/json-logic-php',
            default    => '',
        };
        foreach ($packages as $pkg) {
            if (($pkg['name'] ?? '') === $name) {
                return ltrim($pkg['version'] ?? 'unknown', 'v');
            }
        }
    } catch (\Throwable) {}
    return 'unknown';
}

// ---------------------------------------------------------------------------
// Equality check (mirrors Ruby runner)
// ---------------------------------------------------------------------------

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
        // Normalise both sides to arrays for structural comparison
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
// Run
// ---------------------------------------------------------------------------

$lib_version = get_version($adapter);

// Warmup
for ($i = 0; $i < $warmup_iterations; $i++) {
    foreach ($tests as $test) {
        try {
            call_adapter($adapter, $test['rule'], $test['data']);
        } catch (\Throwable) {}
    }
}

// Collect passed indices (no timing)
$passed_indices = [];
if ($report_indices) {
    foreach ($tests as $idx => $test) {
        $expects_error = $test['error'] !== null;
        $expected      = $test['result'];
        try {
            $result = call_adapter($adapter, $test['rule'], $test['data']);
            if (!$expects_error && results_equal($result, $expected)) {
                $passed_indices[] = $idx;
            } elseif ($expects_error) {
                // returned without exception — only pass if no specific type required
                $expected_type = $test['error']['type'] ?? null;
                if ($expected_type === null) {
                    $passed_indices[] = $idx;
                }
            }
        } catch (\Throwable $e) {
            if ($expects_error) {
                $expected_type = $test['error']['type'] ?? null;
                if ($expected_type === null ||
                    str_contains($e->getMessage(), $expected_type) ||
                    str_contains(get_class($e), $expected_type)) {
                    $passed_indices[] = $idx;
                }
            }
        }
    }
}

// Benchmark with correctness checking
$total_passed      = 0;
$total_failed      = 0;
$total_time_passed = 0.0;
$memory_before     = memory_kb();
$peak_memory_kb    = $memory_before;

for ($iter = 0; $iter < $bench_iterations; $iter++) {
    foreach ($tests as $test) {
        $expects_error = $test['error'] !== null;
        $expected      = $test['result'];

        $start = hrtime(true);
        try {
            $result  = call_adapter($adapter, $test['rule'], $test['data']);
            $elapsed = (hrtime(true) - $start) / 1000; // nanoseconds → microseconds

            if ($expects_error) {
                $total_failed++;
            } elseif (results_equal($result, $expected)) {
                $total_passed++;
                $total_time_passed += $elapsed;
            } else {
                $total_failed++;
            }
        } catch (\Throwable $e) {
            $elapsed = (hrtime(true) - $start) / 1000;

            if ($expects_error) {
                $expected_type = $test['error']['type'] ?? null;
                if ($expected_type === null ||
                    str_contains($e->getMessage(), $expected_type) ||
                    str_contains(get_class($e), $expected_type)) {
                    $total_passed++;
                    $total_time_passed += $elapsed;
                } else {
                    $total_failed++;
                }
            } else {
                $total_failed++;
            }
        }

        $current_mem = memory_kb();
        if ($current_mem > $peak_memory_kb) {
            $peak_memory_kb = $current_mem;
        }
    }
}

$memory_after = memory_kb();
$total_tests  = $total_passed + $total_failed;
$pass_rate    = $total_tests > 0 ? round($total_passed / $total_tests * 100, 2) : 0;
$avg_time_us  = $total_passed > 0 ? round($total_time_passed / $total_passed, 3) : 0;
$ops_per_sec  = $total_passed > 0 ? round($total_passed / ($total_time_passed / 1_000_000), 2) : 0;

$peak_memory_mb  = round($peak_memory_kb / 1024, 2);
$memory_delta_mb = round(($memory_after - $memory_before) / 1024, 2);

echo 'BENCHMARK_RESULT:' . json_encode([
    'version'          => $lib_version,
    'status'           => 'success',
    'total_tests'      => (int)($total_tests / $bench_iterations),
    'passed'           => (int)($total_passed / $bench_iterations),
    'failed'           => (int)($total_failed / $bench_iterations),
    'pass_rate'        => $pass_rate,
    'avg_time_us'      => $avg_time_us,
    'ops_per_second'   => $ops_per_sec,
    'peak_memory_mb'   => $peak_memory_mb,
    'memory_delta_mb'  => $memory_delta_mb,
    'passed_indices'   => $passed_indices,
]);
