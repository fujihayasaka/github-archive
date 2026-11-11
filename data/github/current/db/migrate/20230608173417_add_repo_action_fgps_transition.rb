# typed: true
# frozen_string_literal: true

require "github/transitions/20230608173417_add_repo_action_fgps"

class AddRepoActionFgpsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddRepoActionFgps.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
