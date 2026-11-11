# typed: true
# frozen_string_literal: true

require "github/transitions/20240125175714_move_growth_last_activity_key_values"

class MoveGrowthLastActivityKeyValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveGrowthLastActivityKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
