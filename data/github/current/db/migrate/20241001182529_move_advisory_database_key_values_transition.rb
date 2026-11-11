# typed: true
# frozen_string_literal: true

require "github/transitions/20241001182529_move_advisory_database_key_values"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class MoveAdvisoryDatabaseKeyValuesTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveAdvisoryDatabaseKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
