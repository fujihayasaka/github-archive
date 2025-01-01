# typed: true
# frozen_string_literal: true

require "github/transitions/20241003155448_move_organizations_key_values"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class MoveStragglerOrganizationsKeyValuesTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveOrganizationKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
