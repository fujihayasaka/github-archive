# typed: true
# frozen_string_literal: true

require "github/transitions/20240306211926_add_fgp_actions_usage_metrics_viewer"

class AddFgpActionsUsageMetricsViewerTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddFgpActionsUsageMetricsViewer.new(arguments)
    transition.run
  end

  def self.down
  end
end
