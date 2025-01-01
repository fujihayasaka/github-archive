# typed: true
# frozen_string_literal: true

require "github/transitions/20240819202631_move_users_key_values"

class MoveUsersKeyValuesTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveUsersKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
