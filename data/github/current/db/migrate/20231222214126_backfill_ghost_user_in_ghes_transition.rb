# typed: true
# frozen_string_literal: true

require "github/transitions/20231222214126_backfill_ghost_user_in_ghes"

class BackfillGhostUserInGhesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillGhostUserInGhes.new(arguments)
    transition.run
  end

  def self.down
  end
end
