# typed: true
# frozen_string_literal: true

require "github/transitions/20250324222608_delete_orphaned_rule_suite_source_results"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class DeleteOrphanedRuleSuiteSourceResultsTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DeleteOrphanedRuleSuiteSourceResults.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
