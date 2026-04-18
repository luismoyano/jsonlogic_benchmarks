#!/usr/bin/env crystal
# frozen_string_literal: true

#
# JSON Logic Crystal - Performance & Compatibility Benchmark
# ==========================================================
#
# Reads test suites from ../tests/ (downloaded by scripts/download_tests.sh)
#
# Measures:
#   - Correctness: passed/failed tests
#   - Performance: time only for passed tests
#
# Shards tested:
#   - shiny_json_logic (https://github.com/luismoyano/shiny_json_logic_crystal)
#

require "json"
require "file_utils"
require "shiny_json_logic"

SCRIPT_DIR = File.dirname(Process.executable_path || __FILE__)
ROOT_DIR   = File.dirname(SCRIPT_DIR)
TESTS_DIR  = File.join(ROOT_DIR, "tests")

WARMUP_ITERATIONS    = 10
BENCHMARK_ITERATIONS = 10

def crystal_version : String
  Crystal::VERSION
end

def os_name : String
  {% if flag?(:darwin) %}
    "macos"
  {% elsif flag?(:linux) %}
    "linux"
  {% else %}
    "unknown"
  {% end %}
end

def load_test_suites : Hash(String, Array(JSON::Any))
  all_tests = {} of String => Array(JSON::Any)

  unless Dir.exists?(TESTS_DIR)
    STDERR.puts "ERROR: Tests directory not found: #{TESTS_DIR}"
    STDERR.puts "Run scripts/download_tests.sh first"
    exit 1
  end

  puts "Loading test suites from #{TESTS_DIR}..."

  Dir.glob(File.join(TESTS_DIR, "**", "*.json")).sort.each do |file|
    relative_path = file.sub("#{TESTS_DIR}/", "")
    suite_name = relative_path.gsub("/", "_").gsub(".json", "")

    begin
      raw = JSON.parse(File.read(file))
      next unless raw.raw.is_a?(Array(JSON::Any))
      tests = raw.as_a.select { |item| item.raw.is_a?(Hash(String, JSON::Any)) }
      if tests.any?
        all_tests[suite_name] = tests
        puts "  #{relative_path}: #{tests.size} tests"
      end
    rescue e : JSON::ParseException
      puts "  #{relative_path}: PARSE ERROR - #{e.message}"
    end
  end

  all_tests
end

def flatten_tests(all_tests : Hash(String, Array(JSON::Any))) : Array(JSON::Any)
  all_tests.values.flatten
end

def results_equal(actual : JSON::Any, expected : JSON::Any) : Bool
  ra = actual.raw
  re = expected.raw

  case {ra, re}
  when {Float64, Float64}
    (ra - re).abs < 0.0001
  when {Int64, Float64}
    (ra.to_f - re).abs < 0.0001
  when {Float64, Int64}
    (ra - re.to_f).abs < 0.0001
  when {Array(JSON::Any), Array(JSON::Any)}
    return false unless ra.size == re.size
    ra.zip(re).all? { |a, b| results_equal(a, b) }
  when {Hash(String, JSON::Any), Hash(String, JSON::Any)}
    return false unless ra.size == re.size
    ra.all? { |k, v| re.has_key?(k) && results_equal(v, re[k]) }
  else
    actual == expected
  end
end

def run_shiny_benchmark(tests : Array(JSON::Any), subset_indices : Array(Int32)? = nil, report_passed_indices : Bool = false) : Hash(String, JSON::Any)  test_set = if subset_indices
    subset_indices.map { |i| tests[i] }
  else
    tests
  end

  version = ShinyJsonLogic::VERSION

  # Warmup
  WARMUP_ITERATIONS.times do
    test_set.each do |tc|
      rule = tc.as_h["rule"]
      data = tc.as_h["data"]? || JSON::Any.new(nil)
      begin
        ShinyJsonLogic.apply(rule, data)
      rescue
      end
    end
  end

  # Collect passed indices
  passed_indices = [] of Int32
  if report_passed_indices
    tests.each_with_index do |tc, idx|
      h = tc.as_h
      rule   = h["rule"]
      data   = h["data"]? || JSON::Any.new(nil)
      expected      = h["result"]?
      error_expected = h["error"]?

      begin
        result = ShinyJsonLogic.apply(rule, data)
        if error_expected
          # returned without error — only pass if no specific type required
        elsif expected && results_equal(result, expected)
          passed_indices << idx
        end
      rescue e : ShinyJsonLogic::Errors::Base
        if error_expected
          expected_type = error_expected.as_h["type"]?.try(&.as_s?)
          payload_type  = e.payload["type"]?.try(&.as_s?)
          if expected_type.nil? || expected_type == payload_type
            passed_indices << idx
          end
        end
      rescue
      end
    end
  end

  # Benchmark
  total_passed      = 0
  total_failed      = 0
  total_time_passed = 0.0

  BENCHMARK_ITERATIONS.times do
    test_set.each do |tc|
      h = tc.as_h
      rule           = h["rule"]
      data           = h["data"]? || JSON::Any.new(nil)
      expected       = h["result"]?
      error_expected = h["error"]?

      t0 = Time.monotonic
      begin
        result  = ShinyJsonLogic.apply(rule, data)
        elapsed = (Time.monotonic - t0).total_microseconds

        if error_expected
          total_failed += 1
        elsif expected && results_equal(result, expected)
          total_passed += 1
          total_time_passed += elapsed
        else
          total_failed += 1
        end
      rescue e : ShinyJsonLogic::Errors::Base
        elapsed = (Time.monotonic - t0).total_microseconds
        if error_expected
          expected_type = error_expected.as_h["type"]?.try(&.as_s?)
          payload_type  = e.payload["type"]?.try(&.as_s?)
          if expected_type.nil? || expected_type == payload_type
            total_passed += 1
            total_time_passed += elapsed
          else
            total_failed += 1
          end
        else
          total_failed += 1
        end
      rescue
        total_failed += 1
      end
    end
  end

  total_tests  = total_passed + total_failed
  pass_rate    = total_tests > 0 ? (total_passed.to_f / total_tests * 100).round(2) : 0.0
  ops_per_sec  = total_passed > 0 ? (total_passed.to_f / (total_time_passed / 1_000_000)).round(2) : 0.0

  result = {
    "version"        => JSON::Any.new(version),
    "status"         => JSON::Any.new("success"),
    "total_tests"    => JSON::Any.new((total_tests / BENCHMARK_ITERATIONS).to_i64),
    "passed"         => JSON::Any.new((total_passed / BENCHMARK_ITERATIONS).to_i64),
    "failed"         => JSON::Any.new((total_failed / BENCHMARK_ITERATIONS).to_i64),
    "pass_rate"      => JSON::Any.new(pass_rate),
    "ops_per_second" => JSON::Any.new(ops_per_sec),
    "passed_indices" => JSON::Any.new(passed_indices.map { |i| JSON::Any.new(i.to_i64) }),
  } of String => JSON::Any

  result
end

def format_number(n : Float64) : String
  n.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
end

def main
  puts "=" * 70
  puts "JSON LOGIC CRYSTAL - PERFORMANCE & COMPATIBILITY BENCHMARK"
  puts "=" * 70
  puts
  puts "Crystal version: #{crystal_version}"
  puts "OS: #{os_name}"
  puts "Warmup iterations: #{WARMUP_ITERATIONS}"
  puts "Benchmark iterations: #{BENCHMARK_ITERATIONS}"
  puts

  all_tests = load_test_suites
  total_test_count = all_tests.values.map(&.size).sum
  puts
  puts "Loaded #{all_tests.size} test suites with #{total_test_count} total tests"
  puts

  flat_tests = flatten_tests(all_tests)

  # Mode 1: each shard measured on its own passing tests
  puts "--- Mode 1: shiny_json_logic on its own passing tests ---"
  puts

  print "Benchmarking shiny_json_logic... "
  result = run_shiny_benchmark(flat_tests, report_passed_indices: true)
  pass_rate = result["pass_rate"].as_f
  ops       = result["ops_per_second"].as_f
  puts "#{pass_rate}% pass, #{format_number(ops)} ops/sec"

  puts
  puts "=" * 70
  puts "RESULTS SUMMARY"
  puts "=" * 70
  puts
  puts "| Shard              | Version | Pass Rate | Passed | Failed | Ops/sec     |"
  puts "|--------------------|---------|-----------|--------|--------|-------------|"
  version   = result["version"].as_s
  passed    = result["passed"].as_i
  failed    = result["failed"].as_i
  puts "| #{"shiny_json_logic".ljust(18)} | #{version[0..6].ljust(7)} | #{("#{pass_rate}%").rjust(9)} | #{passed.to_s.rjust(6)} | #{failed.to_s.rjust(6)} | #{format_number(ops).rjust(11)} |"
  puts

  # Save JSON
  timestamp = Time.local
  json_output = {
    "language"         => JSON::Any.new("crystal"),
    "language_version" => JSON::Any.new(crystal_version),
    "os"               => JSON::Any.new(os_name),
    "timestamp"        => JSON::Any.new(timestamp.to_rfc3339),
    "total_tests"      => JSON::Any.new(total_test_count.to_i64),
    "results"          => JSON::Any.new({
      "shiny_json_logic" => JSON::Any.new(result),
    }),
  }

  date_str = timestamp.to_s("%Y-%m-%d")
  dated_dir = File.join(SCRIPT_DIR, "results", date_str)
  latest_dir = File.join(SCRIPT_DIR, "results", "latest")
  FileUtils.mkdir_p(dated_dir)
  FileUtils.mkdir_p(latest_dir)

  filename = "crystal_#{crystal_version}_#{os_name}.json"
  output_path = File.join(dated_dir, filename)
  latest_path = File.join(latest_dir, filename)

  content = json_output.to_json
  File.write(output_path, content)
  File.write(latest_path, content)
  puts "Results saved to: #{output_path}"
end

main
