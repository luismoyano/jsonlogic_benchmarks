#!/usr/bin/env ruby
# frozen_string_literal: true

#
# JSON Logic Ruby Implementations - Performance & Compatibility Benchmark
# ========================================================================
#
# Reads test suites from ../tests/ (downloaded by scripts/download_tests.sh)
#
# Measures:
#   - Correctness: passed/failed tests
#   - Performance: time only for passed tests
#   - Compatibility: percentage of tests passed
#
# Gems tested:
#   - shiny_json_logic (https://rubygems.org/gems/shiny_json_logic)
#   - json-logic-rb (https://rubygems.org/gems/json-logic-rb)
#   - json_logic (https://rubygems.org/gems/json_logic) - bhgames
#   - json_logic_ruby (https://rubygems.org/gems/json_logic_ruby)
#

require 'json'
require 'open3'
require 'fileutils'
require 'time'
require 'tmpdir'

SCRIPT_DIR = File.dirname(__FILE__)
ROOT_DIR = File.dirname(SCRIPT_DIR)
TESTS_DIR = File.join(ROOT_DIR, 'tests')

# Number of iterations for timing
WARMUP_ITERATIONS = 2
BENCHMARK_ITERATIONS = 5

# Gems to benchmark
GEMS = {
  'shiny_json_logic' => {
    gem: 'shiny_json_logic',
    require: 'shiny_json_logic',
    call: 'ShinyJsonLogic.apply(logic, data)',
    version_call: 'ShinyJsonLogic::VERSION',
    min_ruby: '2.7'
  },
  'json-logic-rb' => {
    gem: 'json-logic-rb',
    require: 'json_logic',
    call: 'JsonLogic.apply(logic, data)',
    version_call: 'JsonLogic::VERSION',
    min_ruby: '3.0'
  },
  'json_logic' => {
    gem: 'json_logic',
    require: 'json_logic',
    call: 'JSONLogic.apply(logic, data)',
    version_call: 'JSONLogic::VERSION',
    min_ruby: '2.2'
  },
  'json_logic_ruby' => {
    gem: 'json_logic_ruby',
    require: 'json_logic',
    call: 'JsonLogic::Evaluator.new.apply(logic, data)',
    version_call: 'JsonLogic::VERSION',
    min_ruby: '3.2'
  }
}

def ruby_version
  RUBY_VERSION
end

def load_test_suites
  all_tests = {}
  
  unless Dir.exist?(TESTS_DIR)
    puts "ERROR: Tests directory not found: #{TESTS_DIR}"
    puts "Run scripts/download_tests.sh first"
    exit 1
  end
  
  puts "Loading test suites from #{TESTS_DIR}..."
  
  # Find all JSON files recursively
  Dir.glob(File.join(TESTS_DIR, '**', '*.json')).each do |file|
    # Create suite name from relative path
    relative_path = file.sub("#{TESTS_DIR}/", '')
    suite_name = relative_path.gsub('/', '_').gsub('.json', '')
    
    begin
      raw = JSON.parse(File.read(file))
      # Filter out comment strings, keep only test objects
      tests = raw.select { |item| item.is_a?(Hash) }
      
      if tests.any?
        all_tests[suite_name] = tests
        puts "  #{relative_path}: #{tests.size} tests"
      end
    rescue JSON::ParserError => e
      puts "  #{relative_path}: PARSE ERROR - #{e.message}"
    end
  end
  
  all_tests
end

def generate_benchmark_script(gem_config, all_tests)
  # Flatten all tests into a single array
  flattened_tests = []
  all_tests.each do |suite_name, tests|
    tests.each do |test|
      flattened_tests << {
        'rule' => test['rule'],
        'data' => test['data'],
        'result' => test['result'],
        'error' => test['error']
      }
    end
  end
  
  tests_json = JSON.generate(flattened_tests)

  <<~RUBY
    $stdout = File.open(File::NULL, 'w')
    $stderr = File.open(File::NULL, 'w')

    require 'bundler/inline'

    begin
      gemfile(quiet: true) do
        source 'https://rubygems.org'
        gem '#{gem_config[:gem]}'
      end
    rescue => e
      $stdout = STDOUT
      puts "BENCHMARK_RESULT:" + { status: 'error', error: e.message }.to_json
      exit 0
    end

    $stdout = STDOUT
    $stderr = STDERR

    require '#{gem_config[:require]}'
    require 'json'

    gem_version = begin
      #{gem_config[:version_call]}
    rescue
      'unknown'
    end

    TESTS = JSON.parse(<<-'JSON_END'
    #{tests_json}
    JSON_END
    )

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

    # Memory measurement (cross-platform: Linux and macOS)
    def memory_kb
      `ps -o rss= -p \#{Process.pid}`.to_i
    end

    # Warmup
    #{WARMUP_ITERATIONS}.times do
      TESTS.each do |test|
        begin
          #{gem_config[:call].gsub('logic', 'test["rule"]').gsub('data', 'test["data"]')}
        rescue
        end
      end
    end

    # Benchmark with correctness checking
    total_passed = 0
    total_failed = 0
    total_time_passed = 0.0
    peak_memory_kb = memory_kb
    memory_before = memory_kb

    #{BENCHMARK_ITERATIONS}.times do
      TESTS.each do |test|
        logic = test['rule']
        data = test['data']
        expects_error = !test['error'].nil?
        expected = test['result']

        begin
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = #{gem_config[:call]}
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
          
          # Track peak memory
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
          
          # Track peak memory
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
    
    # Memory metrics
    peak_memory_mb = (peak_memory_kb / 1024.0).round(2)
    memory_delta_mb = ((memory_after - memory_before) / 1024.0).round(2)
    # Memory per operation (bytes per passed test, averaged over iterations)
    memory_per_op_bytes = total_passed > 0 ? (((memory_after - memory_before) * 1024.0) / (total_passed / #{BENCHMARK_ITERATIONS})).round(2) : 0

    puts "BENCHMARK_RESULT:" + JSON.generate({
      version: gem_version,
      status: 'success',
      total_tests: total_tests / #{BENCHMARK_ITERATIONS},
      passed: total_passed / #{BENCHMARK_ITERATIONS},
      failed: total_failed / #{BENCHMARK_ITERATIONS},
      pass_rate: pass_rate,
      avg_time_us: avg_time_per_passed_us,
      ops_per_second: ops_per_second,
      peak_memory_mb: peak_memory_mb,
      memory_delta_mb: memory_delta_mb,
      memory_per_op_bytes: memory_per_op_bytes
    })
  RUBY
end

def run_benchmark(gem_name, gem_config, all_tests)
  current = Gem::Version.new(ruby_version)
  min_required = Gem::Version.new(gem_config[:min_ruby])

  if current < min_required
    return {
      'status' => 'incompatible',
      'error' => "Requires Ruby >= #{gem_config[:min_ruby]}",
      'min_ruby_version' => gem_config[:min_ruby]
    }
  end

  script = generate_benchmark_script(gem_config, all_tests)
  ruby_exe = RbConfig.ruby

  Dir.mktmpdir do |tmpdir|
    script_file = File.join(tmpdir, 'benchmark.rb')
    File.write(script_file, script)

    stdout, stderr, status = Open3.capture3(ruby_exe, script_file, chdir: tmpdir)

    if stdout.include?('BENCHMARK_RESULT:')
      json_str = stdout.split('BENCHMARK_RESULT:').last.strip
      begin
        return JSON.parse(json_str)
      rescue JSON::ParserError
        return { 'status' => 'error', 'error' => "Invalid JSON: #{json_str[0..100]}" }
      end
    end

    stderr_clean = stderr.lines.reject { |l| l.include?('warning:') }.join.strip

    unless status.success?
      return { 'status' => 'error', 'error' => stderr_clean.empty? ? 'Unknown error' : stderr_clean[0..200] }
    end

    { 'status' => 'error', 'error' => "No benchmark result found" }
  end
end

def format_number(n)
  n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end

def main
  puts "=" * 70
  puts "JSON LOGIC RUBY - PERFORMANCE & COMPATIBILITY BENCHMARK"
  puts "=" * 70
  puts
  puts "Ruby version: #{RUBY_VERSION}"
  puts "Ruby platform: #{RUBY_PLATFORM}"
  puts "Warmup iterations: #{WARMUP_ITERATIONS}"
  puts "Benchmark iterations: #{BENCHMARK_ITERATIONS}"
  puts

  # Load test suites from shared tests/ directory
  all_tests = load_test_suites

  total_test_count = all_tests.values.map(&:size).sum
  puts
  puts "Loaded #{all_tests.size} test suites with #{total_test_count} total tests"
  puts

  results = {}

  GEMS.each do |gem_name, gem_config|
    print "Benchmarking #{gem_name}... "
    $stdout.flush

    result = run_benchmark(gem_name, gem_config, all_tests)
    results[gem_name] = result

    case result['status']
    when 'incompatible'
      puts "SKIP (#{result['error']})"
    when 'error'
      puts "ERROR (#{result['error'][0..50]})"
    else
      pass_rate = result['pass_rate'] || 0
      ops = result['ops_per_second'] || 0
      peak_mem = result['peak_memory_mb'] || 0
      puts "#{pass_rate}% pass, #{format_number(ops.to_i)} ops/sec, #{peak_mem} MB peak"
    end
  end

  puts
  puts "=" * 70
  puts "RESULTS SUMMARY"
  puts "=" * 70
  puts

  # Sort by pass rate, then by ops/sec
  sorted = results.sort_by do |name, r|
    if r['status'] == 'success'
      [-(r['pass_rate'] || 0), -(r['ops_per_second'] || 0)]
    else
      [0, 0]
    end
  end

  puts "| Gem                  | Version | Pass Rate | Passed | Failed | Ops/sec     | Peak Mem  |"
  puts "|----------------------|---------|-----------|--------|--------|-------------|-----------|"

  sorted.each do |gem_name, result|
    case result['status']
    when 'incompatible'
      puts "| #{gem_name.ljust(20)} | -       | INCOMPATIBLE - #{result['error'].ljust(45)} |"
    when 'error'
      puts "| #{gem_name.ljust(20)} | -       | ERROR - #{result['error'][0..50].ljust(50)} |"
    else
      version = (result['version'] || 'unknown')[0..6]
      pass_rate = "#{result['pass_rate']}%"
      passed = result['passed'] || 0
      failed = result['failed'] || 0
      ops = format_number((result['ops_per_second'] || 0).to_i)
      peak_mem = "#{result['peak_memory_mb']} MB"

      puts "| #{gem_name.ljust(20)} | #{version.ljust(7)} | #{pass_rate.rjust(9)} | #{passed.to_s.rjust(6)} | #{failed.to_s.rjust(6)} | #{ops.rjust(11)} | #{peak_mem.rjust(9)} |"
    end
  end

  puts
  puts "Legend:"
  puts "  Pass Rate = percentage of tests passed"
  puts "  Ops/sec   = operations per second (passed tests only)"
  puts "  Peak Mem  = peak memory usage during benchmark"
  puts

  # Output JSON
  json_output = {
    'language' => 'ruby',
    'language_version' => RUBY_VERSION,
    'platform' => RUBY_PLATFORM,
    'timestamp' => Time.now.iso8601,
    'total_tests' => total_test_count,
    'results' => results
  }

  results_dir = File.join(SCRIPT_DIR, 'results')
  FileUtils.mkdir_p(results_dir)

  output_file = File.join(results_dir, "ruby_#{RUBY_VERSION}.json")
  File.write(output_file, JSON.pretty_generate(json_output))
  puts "Results saved to: #{output_file}"
end

main
