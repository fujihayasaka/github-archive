#!/usr/bin/env safe-ruby
# frozen_string_literal: true

require_relative "../config/environment"

feature_flags = %w[
  copilot_pipes
  copilot_pipes_github_graphql_nodes
]

puts "Enabling #{feature_flags.length} feature #{'flag'.pluralize(feature_flags.length)}:"
puts

feature_flags.each do |feature_flag|
  if GitHub.flipper[feature_flag].enable
    puts "  ✅ #{feature_flag} enabled"
  else
    puts "  ❌ #{feature_flag} could not be enabled"
  end
end

puts
puts "Pipes is set up! 🚀"
