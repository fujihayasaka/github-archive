# typed: true
# frozen_string_literal: true

require "github/transitions/20230112165045_backfill_ghes_repo_dependabot_alerts_enablement"

class BackfillGhesRepoDependabotAlertsEnablementTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillGhesRepoDependabotAlertsEnablement.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
