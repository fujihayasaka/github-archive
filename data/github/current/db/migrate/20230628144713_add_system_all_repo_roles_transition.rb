# typed: true
# frozen_string_literal: true

require "github/transitions/20230628144713_add_system_all_repo_roles"

class AddSystemAllRepoRolesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddSystemAllRepoRoles.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
