# typed: true
# frozen_string_literal: true

require "github/transitions/20231031172844_backfill_dependabot_default_rule"

class BackfillDependabotDefaultRuleTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillDependabotDefaultRule.new(arguments)
    transition.perform
  end

  def self.down
  end
end
