#!/usr/bin/env safe-ruby
# frozen_string_literal: true

require_relative "../config/environment"

feature_flags = %w[
  copilot_pipes
  copilot_pipes_github_graphql_nodes
  loops_service
  loops_react_query_devtools
  copilot_loops_post_staff_ship_features
  loops_versioning
  loops_remove_browser_storage
  loops_document_per_loop_body
  copilot_loops_share_button
  copilot_chat_no_header
]

puts "Enabling #{feature_flags.length} feature #{'flag'.pluralize(feature_flags.length)}:"
puts

feature_flags.each do |feature_flag|
  FeatureFlag.vexi_management.enable_feature_flag(feature_flag)

  if FeatureFlag.vexi.enabled?(feature_flag, default: false)
    puts "  ✅ #{feature_flag} enabled"
  else
    puts "  ❌ #{feature_flag} could not be enabled"
  end
end
