#!/usr/bin/env ruby
# frozen_string_literal: true

#
# benchmark_runner.rb — isolated per-gem benchmark subprocess
# ===========================================================
#
# Invoked by performance_benchmark.rb (or local_benchmark.rb) as a subprocess.
# Receives a JSON config via ARGV[0].
#
# Config keys:
#   gem               - gem name for bundler/inline (e.g. 'shiny_json_logic')
#   local_path        - (optional) load gem from local path instead of RubyGems
#   require           - file to require (e.g. 'shiny_json_logic')
#   adapter           - which call adapter to use (e.g. 'shiny_json_logic')
#   tests             - array of {rule, data, result, error} hashes
#   warmup_iterations - integer
#   benchmark_iterations - integer
#   report_passed_indices - boolean
#

require 'json'

$stdout = File.open(File::NULL, 'w')
$stderr = File.open(File::NULL, 'w')

require 'bundler/inline'

config = JSON.parse(ARGV[0])

begin
  gemfile(quiet: true) do
    source 'https://rubygems.org'
    if config['local_path']
      gem config['gem'], path: config['local_path']
    else
      gem config['gem']
    end
  end
rescue => e
  $stdout = STDOUT
  puts 'BENCHMARK_RESULT:' + { status: 'error', error: e.message }.to_json
  exit 0
end

$stdout = STDOUT
$stderr = STDERR

require config['require']

ADAPTER           = config['adapter']
TESTS             = config['tests']
WARMUP_ITERATIONS = config['warmup_iterations']
BENCH_ITERATIONS  = config['benchmark_iterations']
REPORT_INDICES    = config['report_passed_indices']

gem_version = begin
  case ADAPTER
  when 'shiny_json_logic' then ShinyJsonLogic::VERSION
  when 'json-logic-rb'    then JsonLogic::VERSION
  when 'json_logic'       then JSONLogic::VERSION
  when 'json_logic_ruby'  then JsonLogic::VERSION
  else 'unknown'
  end
rescue
  'unknown'
end

def call_adapter(adapter, logic, data)
  case adapter
  when 'shiny_json_logic' then ShinyJsonLogic.apply(logic, data)
  when 'json-logic-rb'    then JsonLogic.apply(logic, data)
  when 'json_logic'       then JSONLogic.apply(logic, data)
  when 'json_logic_ruby'  then JsonLogic::Evaluator.new.apply(logic, data)
  else raise "Unknown adapter: #{adapter}"
  end
end

def results_equal?(actual, expected)
  if expected.is_a?(Float) && actual.is_a?(Float)
    (actual - expected).abs < 0.0001
  elsif expected.is_a?(Array) && actual.is_a?(Array)
    return false unless expected.size == actual.size

    expected.zip(actual).all? { |e, a| results_equal?(a, e) }
  elsif expected.is_a?(Hash) && actual.is_a?(Hash)
    return false unless expected.keys.sort == actual.keys.sort

    expected.keys.all? { |k| results_equal?(actual[k], expected[k]) }
  else
    actual == expected
  end
end

def memory_kb
  `ps -o rss= -p #{Process.pid}`.to_i
end

# Warmup
WARMUP_ITERATIONS.times do
  TESTS.each do |test|
    begin
      call_adapter(ADAPTER, test['rule'], test['data'])
    rescue
    end
  end
end

# Collect passed indices (first pass, no timing)
passed_indices = []
if REPORT_INDICES
  passed_indices_set = {}
  TESTS.each_with_index do |test, idx|
    expects_error = !test['error'].nil?
    expected = test['result']
    begin
      result = call_adapter(ADAPTER, test['rule'], test['data'])
      if !expects_error && results_equal?(result, expected)
        passed_indices_set[idx] = true
      elsif expects_error
        expected_type = test.dig('error', 'type')
        passed_indices_set[idx] = true if expected_type.nil? || result.nil?
      end
    rescue => e
      if expects_error
        expected_type = test.dig('error', 'type')
        passed_indices_set[idx] = true if expected_type.nil? || e.message.include?(expected_type.to_s) || e.class.to_s.include?(expected_type.to_s)
      end
    end
  end
  passed_indices = passed_indices_set.keys
end

# Benchmark with correctness checking
total_passed = 0
total_failed = 0
total_time_passed = 0.0
peak_memory_kb = memory_kb
memory_before = memory_kb

BENCH_ITERATIONS.times do
  TESTS.each do |test|
    logic = test['rule']
    data = test['data']
    expects_error = !test['error'].nil?
    expected = test['result']

    begin
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = call_adapter(ADAPTER, logic, data)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      elapsed_us = elapsed * 1_000_000

      if expects_error
        total_failed += 1
      elsif results_equal?(result, expected)
        total_passed += 1
        total_time_passed += elapsed_us
      else
        total_failed += 1
      end

      current_mem = memory_kb
      peak_memory_kb = current_mem if current_mem > peak_memory_kb
    rescue => e
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time rescue 0
      elapsed_us = elapsed * 1_000_000

      if expects_error
        expected_type = test.dig('error', 'type')
        if expected_type.nil? || e.message.include?(expected_type.to_s) || e.class.to_s.include?(expected_type.to_s)
          total_passed += 1
          total_time_passed += elapsed_us
        else
          total_failed += 1
        end
      else
        total_failed += 1
      end

      current_mem = memory_kb
      peak_memory_kb = current_mem if current_mem > peak_memory_kb
    end
  end
end

# Calculate metrics
memory_after = memory_kb
total_tests = total_passed + total_failed
pass_rate = total_tests > 0 ? (total_passed.to_f / total_tests * 100).round(2) : 0
avg_time_per_passed_us = total_passed > 0 ? (total_time_passed / total_passed).round(3) : 0
ops_per_second = total_passed > 0 ? (total_passed / (total_time_passed / 1_000_000)).round(2) : 0

peak_memory_mb = (peak_memory_kb / 1024.0).round(2)
memory_delta_mb = ((memory_after - memory_before) / 1024.0).round(2)
memory_per_op_bytes = total_passed > 0 ? (((memory_after - memory_before) * 1024.0) / (total_passed / BENCH_ITERATIONS)).round(2) : 0

puts 'BENCHMARK_RESULT:' + JSON.generate({
  version: gem_version,
  status: 'success',
  total_tests: total_tests / BENCH_ITERATIONS,
  passed: total_passed / BENCH_ITERATIONS,
  failed: total_failed / BENCH_ITERATIONS,
  pass_rate: pass_rate,
  avg_time_us: avg_time_per_passed_us,
  ops_per_second: ops_per_second,
  peak_memory_mb: peak_memory_mb,
  memory_delta_mb: memory_delta_mb,
  memory_per_op_bytes: memory_per_op_bytes,
  passed_indices: passed_indices
})
