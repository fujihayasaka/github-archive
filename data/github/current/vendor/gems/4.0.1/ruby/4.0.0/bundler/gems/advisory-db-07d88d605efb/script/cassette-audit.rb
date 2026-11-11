#!/usr/bin/env ruby
# frozen_string_literal: true

if ARGV.include?("--help") || ARGV.include?("-h")
  puts "A small utility to identify unused vcr cassettes"
  puts ""
  puts "Prints out a list of cassette files that it could not find direct references to in calls to `VCR.use_cassette(...)` in test files. It is recommended that you perform additional checks before deleting identified files to make sure none of them are referenced dynamically."
  puts ""
  puts "Option Flags:"
  puts "  --help, -h           Show this help message"
  puts "  --verbose, -v        Print additional info about the scan"
  puts "  --keep-app-root, -k  Keep the `/app/` prefix on cassette paths when run from docker/codespaces"
  puts ""
  puts "Examples:"
  puts ""
  puts "Ensure `script/setup` has been run first, then:"
  puts ""
  puts "To run from local checkout:"
  puts ""
  puts "  script/cassette-audit.rb [options]"
  puts ""
  puts "To run from a docker container or in codespaces:"
  puts ""
  puts "  script/app-env script/cassette-audit.rb [options]"

  exit 1
end

require_relative "../config/environment"

unless Rails.env.development?
  puts "This can only be run in the development environment!"
  exit 1
end

verbose = ARGV.include?("--verbose") || ARGV.include?("-v")
deappify = !(ARGV.include?("--keep-app-root") || ARGV.include?("-k"))

puts "Scanning..." if verbose

tests_root = Rails.root.join("test/")
cassettes_root = tests_root.join("cassettes/")
cassette_map = Dir.glob(cassettes_root.join("**/*.{yaml,yml}")).each_with_object({}) do |file_name, hash|
  key = file_name.delete_prefix(cassettes_root.to_s).delete_suffix(".yml") # Get the file name w/o extension
  file_name.delete_prefix!("/app/") if deappify
  hash[key] = file_name
end
puts "Discovered #{cassette_map.size} cassette file(s)" if verbose

test_files = Dir.glob(tests_root.join("**/*.rb")).to_set
puts "Searching through #{test_files.size} test file(s)" if verbose

dynamic_cassettes = []
test_files.each do |test_file_name|
  puts "Scanning #{test_file_name}" if verbose
  lines = File.readlines(test_file_name)
  lines.each_with_index do |line, line_number|
    if (match = line.match(/\bVCR\.use_cassette\((["'])([^\1]*#\{[^}]+\}[^\1]*)\1(?:,.+)?\)/))
      dynamic_match = match[2]

      puts "Found dynamic cassette `#{dynamic_match}`" if verbose

      dynamic_cassette_location = test_file_name.dup
      dynamic_cassette_location.delete_prefix!("/app/") if deappify
      dynamic_cassette_location += ":#{line_number + 1}"
      dynamic_cassettes << [dynamic_match, dynamic_cassette_location]
    elsif (match = line.match(/\bVCR\.use_cassette\((["'])([^\1]+)\1(?:,.+)?\)/))
      # normalize file names the way VCR would (probably)
      found_cassette = match[2]
      normalized_cassette = found_cassette.gsub(/[^\w-]/, "_")

      if verbose
        found_cassette += " (normalized to #{normalized_cassette})" if found_cassette != normalized_cassette
        puts "Found reference to #{found_cassette}"
      end

      cassette_map.delete(normalized_cassette)
    end
  end
end

if cassette_map.any?
  if verbose
    puts "Scan complete."
    puts "References for #{cassette_map.size} cassette file(s) were not found while scanning test files."
    puts ""
  end

  puts cassette_map.values

  if verbose && dynamic_cassettes.any?
    puts ""
    puts "We also found references to #{dynamic_cassettes.size} dynamic cassette(s) references."
    puts "You should cross check these with the cassettes names above to ensure they are not in use before removing."
    puts ""

    puts(dynamic_cassettes.map { |ary| ary.join(", ") })
  end
elsif verbose
  puts "Scan complete. No unreference cassette files were found."
end
