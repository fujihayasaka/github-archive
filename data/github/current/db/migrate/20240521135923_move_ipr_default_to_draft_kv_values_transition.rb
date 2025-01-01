# typed: true
# frozen_string_literal: true

require "github/transitions/20240521135923_move_ipr_default_to_draft_kv_values"

class MoveIprDefaultToDraftKvValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveIprDefaultToDraftKvValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
