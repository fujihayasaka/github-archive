# typed: true
# frozen_string_literal: true

require "github/transitions/20250312200822_move_actions_key_values"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class MoveActionsKeyValuesTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveActionsKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
