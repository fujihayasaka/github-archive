# typed: true
# frozen_string_literal: true

require "github/transitions/20231204222922_fix_pull_request_alert_locations"

class FixPullRequestAlertLocationsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::FixPullRequestAlertLocations.new(arguments)
    transition.run
  end

  def self.down
  end
end
