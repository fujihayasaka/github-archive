# typed: true
require "github/transitions/20210917113644_set_organization_wide_write_access_to_projects"

class SetOrganizationWideWriteAccessToProjectsTransitionForBaseRole < ActiveRecord::Migration[7.1]
  def self.up
    return unless GitHub.enterprise?
    transition = GitHub::Transitions::SetOrganizationWideWriteAccessToProjects.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
