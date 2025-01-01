# typed: true
# frozen_string_literal: true

require "github/transitions/20231204133754_backfill_rule_suite_owner_id"

class BackfillRuleSuiteOwnerIdTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillRuleSuiteOwnerId.new(arguments)
    transition.run
  end

  def self.down
  end
end
