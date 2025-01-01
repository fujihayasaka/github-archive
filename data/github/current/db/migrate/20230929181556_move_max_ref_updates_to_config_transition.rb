# typed: true
# frozen_string_literal: true

require "github/transitions/20230929181556_move_max_ref_updates_to_config"

class MoveMaxRefUpdatesToConfigTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveMaxRefUpdatesToConfig.new(arguments)
    transition.run
  end

  def self.down
  end
end
