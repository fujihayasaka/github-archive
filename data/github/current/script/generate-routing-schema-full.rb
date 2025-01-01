#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# generate-routing-schema-full.rb
#
# This script is a wrapper that calls both rate limit data generation
# and the main routing schema generation in the correct order.
#
# Usage: script/generate-routing-schema-full.rb
#

require "pathname"

# Get the absolute path to the script directory
script_dir = File.expand_path(File.dirname(__FILE__))

# Define paths to the scripts
rate_limit_script = File.join(script_dir, "generate-routing-schema-rate-limit-data.rb")
main_script = File.join(script_dir, "generate-routing-schema.rb")

# Check if scripts exist
unless File.exist?(rate_limit_script)
  puts "Error: Rate limit script not found at #{rate_limit_script}"
  exit 1
end

unless File.exist?(main_script)
  puts "Error: Main routing schema script not found at #{main_script}"
  exit 1
end

# Execute the rate limit data generation script
puts "Step 1/2: Generating rate limit data..."
puts "Running: #{rate_limit_script}"
rate_limit_result = system(rate_limit_script)

unless rate_limit_result
  puts "Error: Failed to generate rate limit data. Exiting."
  exit 1
end

puts "\nStep 1/2 completed successfully."

# Execute the main routing schema generation script
puts "\nStep 2/2: Generating main routing schema..."
puts "Running: #{main_script}"
main_result = system(main_script)

unless main_result
  puts "Error: Failed to generate main routing schema. Exiting."
  exit 1
end

puts "\nStep 2/2 completed successfully."
puts "\nFull routing schema generation completed successfully!"
puts "The following files have been generated:"
puts "  - app/api/gateway-routes-primary-rate-limits.yaml"
puts "  - app/api/gateway-routes.yaml"
