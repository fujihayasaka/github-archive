# typed: true
# frozen_string_literal: true

require "github/transitions/20240603180818_transition_last_check_completed_at"

class TransitionLastCheckCompletedAtTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::TransitionLastCheckCompletedAt.new(arguments)
    transition.run
  end

  def self.down
  end
end
