# typed: true
# frozen_string_literal: true

# Profile test boot + execution with Vernier. Invoked by script/profile-test.

require "vernier"
require "fileutils"

interval = Integer(ENV.fetch("INTERVAL", 10_000))
timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
output = ENV.fetch("OUTPUT", "tmp/vernier/profile-boot-#{timestamp}.vernier.json")

test_files = ARGV.dup
ARGV.clear

if test_files.empty?
  abort <<~USAGE
    Usage: script/profile-test TEST_FILE [TEST_FILE ...]

    Profiles test boot + execution with Vernier.

    Environment variables:
      INTERVAL  Sampling interval in µs (default: 10000)
      OUTPUT    Output file path
  USAGE
end

FileUtils.mkdir_p(File.dirname(output))

# Add test/ to load path so `require "test_helper"` works (same as bin/rails test)
$LOAD_PATH.unshift(File.expand_path("../test", __dir__))

# The rails test command loads this reporter class; load it here so test_helper
# can reference it when not run through `bin/rails test`.
require "rails/test_unit/reporter"

$stderr.puts "Profiling with Vernier (interval: #{interval}µs)"
$stderr.puts "Output: #{output}"
$stderr.puts "Test files: #{test_files.join(", ")}"
$stderr.puts

collector = Vernier::Collector.new(:wall, interval: interval, hooks: [:rails])
collector.start

at_exit do
  result = collector.stop
  result.write(out: output)
  $stderr.puts
  $stderr.puts "Vernier profile saved to #{output}"
  $stderr.puts "View at https://vernier.prof or run: vernier view #{output}"
end

test_files.each do |f|
  require File.expand_path(f)
end
