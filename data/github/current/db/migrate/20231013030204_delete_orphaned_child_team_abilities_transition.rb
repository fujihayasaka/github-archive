# typed: true
# frozen_string_literal: true

require "github/transitions/20231013030204_delete_orphaned_child_team_abilities"

class DeleteOrphanedChildTeamAbilitiesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DeleteOrphanedChildTeamAbilities.new(arguments)
    transition.run
  end

  def self.down
  end
end
