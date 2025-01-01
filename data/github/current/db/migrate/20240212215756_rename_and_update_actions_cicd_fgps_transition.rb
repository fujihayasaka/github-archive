# typed: true
# frozen_string_literal: true

require "github/transitions/20240212215756_rename_and_update_actions_cicd_fgps"

class RenameAndUpdateActionsCicdFgpsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::RenameAndUpdateActionsCicdFgps.new(arguments)
    transition.run
  end

  def self.down
  end
end
