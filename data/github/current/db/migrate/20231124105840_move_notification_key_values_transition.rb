# typed: true
# frozen_string_literal: true

require "github/transitions/20231124105840_move_notification_key_values"

class MoveNotificationKeyValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveNotificationKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
