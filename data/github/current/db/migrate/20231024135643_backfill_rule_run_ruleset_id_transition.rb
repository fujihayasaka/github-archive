# typed: true
# frozen_string_literal: true

require "github/transitions/20231024135643_backfill_rule_run_ruleset_id"

class BackfillRuleRunRulesetIdTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillRuleRunRulesetId.new(arguments)
    transition.run
  end

  def self.down
  end
end
