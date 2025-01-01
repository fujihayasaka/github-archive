# typed: true
# frozen_string_literal: true

module Repository::ProjectsSettingsDependency
  extend ActiveSupport::Concern
  class CannotEnableProjectsError < StandardError; end

  include Repository::ProjectsDependency
  include Repository::MemexesDependency

  included do
    alias_method :has_projects=, :has_projects_enabled=
    alias_method :has_projects, :has_projects_enabled?
  end

  def async_has_projects_enabled?
    Promise.resolve(has_projects_enabled?)
  end

  def has_projects_enabled?
    org_projects_enabled = owner&.organization? ? T.cast(owner, Organization).organization_projects_enabled? : true
    return true if repository_memex_projects_enabled? && GitHub.projects_new_enabled? && org_projects_enabled
    repository_projects_enabled? && (!GitHub.projects_new_enabled? || has_any_projects?)
  end

  def has_projects_enabled=(new_value)
    begin
      set_has_repository_projects(new_value)
    rescue Repository::ProjectsDependency::CannotEnableProjectsError
      cannot_enable_projects = true
    end

    begin
      set_has_repository_memex_projects(new_value)
    rescue Repository::MemexesDependency::CannotEnableProjectsError
      cannot_enable_memex_projects = true
    end

    if cannot_enable_projects && cannot_enable_memex_projects
      raise Repository::ProjectsSettingsDependency::CannotEnableProjectsError
    end
  end
end
