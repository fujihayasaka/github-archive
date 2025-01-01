#!/usr/bin/env safe-ruby
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../config/environment"

# List of feature flags that we want to ignore for setting up development environment.
ignored_feature_flags = [
  # Disables the Projects Without Limits experience
  "memex_table_without_limits_disabled",
  "memex_without_limits_kill_switch"
]

feature_flags = [
  *MemexesHelper::MEMEX_CLIENT_FEATURE_FLAGS,
  *MemexesHelper::MEMEX_BACKEND_FEATURE_FLAGS,
  *MemexesHelper::MEMEX_FEATURE_PREVIEWS,
].collect(&:to_s)

puts "Enabling #{feature_flags.length} feature #{'flag'.pluralize(feature_flags.length)}:"
puts

feature_flags.each do |feature_flag|
  if ignored_feature_flags.include?(feature_flag)
    puts "  ⏩ #{feature_flag} is ignored"
  elsif GitHub.flipper[feature_flag].enable
    puts "  ✅ #{feature_flag} enabled"
  else
    puts "  ❌ #{feature_flag} could not be enabled"
  end
end

if MemexesHelper::MEMEX_FEATURE_PREVIEWS.any?
  puts "Enable memex feature previews"
  MemexesHelper::MEMEX_FEATURE_PREVIEWS.each do |feature_preview|
    if Feature.find_by(slug: feature_preview)
      puts "  ⏩ #{feature_preview} already exists"
      next
    end

    Feature.create(
      public_name: feature_preview.to_s,
      slug: feature_preview,
      flipper_feature: FlipperFeature.find_by(name: feature_preview),
      feedback_link: "https://github.com",
      enrolled_by_default: true
    )
    puts "  ✅ #{feature_preview} enabled"
  end
end


puts
puts "Memex is set up! 🚀"
puts
puts "From '/workspaces/github':"
puts "  - Start the dotcom server: script/server"
puts "  - Get up and running quickly with a small sample project: bin/seed memex_projects --count=10"
puts "  - Or seed a real world project with 100 items and 10 columns: bin/seed memex_projects --p50"
puts "  - After creating a project, ensure the project items are indexed by running: bin/elastomer repair"
