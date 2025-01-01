# typed: true
# frozen_string_literal: true

require "github/transitions/20230205062752_remove_discussions_locked_state"

class RemoveDiscussionsLockedStateTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::RemoveDiscussionsLockedState.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
