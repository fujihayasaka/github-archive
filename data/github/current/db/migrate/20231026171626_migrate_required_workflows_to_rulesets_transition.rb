# typed: true
# frozen_string_literal: true

require "github/transitions/20231026171626_migrate_required_workflows_to_rulesets"

class MigrateRequiredWorkflowsToRulesetsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MigrateRequiredWorkflowsToRulesets.new(arguments)
    transition.run
  end

  def self.down
  end
end
