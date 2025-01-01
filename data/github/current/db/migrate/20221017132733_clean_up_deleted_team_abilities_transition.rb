# typed: true
# frozen_string_literal: true

require "github/transitions/20221017132733_clean_up_deleted_team_abilities"

class CleanUpDeletedTeamAbilitiesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::CleanUpDeletedTeamAbilities.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
