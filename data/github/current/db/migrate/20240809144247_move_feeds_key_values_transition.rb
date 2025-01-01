# typed: true
# frozen_string_literal: true

require "github/transitions/20240809144247_move_feeds_key_values"

class MoveFeedsKeyValuesTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveFeedsKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
