# typed: true
# frozen_string_literal: true

require "github/transitions/20230223164004_add_dependabot_alert_fgps"

class AddDependabotAlertFgpsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::AddDependabotAlertFgps.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
