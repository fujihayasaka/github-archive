# typed: false
# frozen_string_literal: true

module Organization::ProjectsDependency
  extend ActiveSupport::Concern

  include Configurable::DisableOrganizationProjects
  include Configurable::DisableRepositoryProjects

  attr_writer :has_repository_projects
  attr_writer :has_organization_projects

  alias_method :projects_enabled?, :organization_projects_enabled?
  alias_method :async_projects_enabled?, :async_organization_projects_enabled?

  class_methods do
    # Public: Get IDs for organizations that have disabled organization-level projects.
    #
    # org_ids - a list of Organization IDs to check
    #
    # Returns an Array of Integer Organization IDs.
    def ids_with_organization_projects_disabled(org_ids)
      return [] unless org_ids.present?
      Configuration::Entry
        .targeting_user_ids(org_ids)
        .named(Configurable::DisableOrganizationProjects::KEY)
        .with_value("TRUE")
        .pluck(:target_id)
    end
  end

  def visible_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.visible_projects_for", tags: ["owner_type:organization"]) do
      # Logged-out users can only see public projects.
      return projects.where(public: true) if user.nil?

      # Bots with the correct permissions can see all of the organization's
      # projects.
      return projects.scoped if user.can_have_granular_permissions? && resources.organization_projects.readable_by?(user.installation)

      # Org owners can see all of the organization's projects
      return projects.scoped if adminable_by?(user)

      available_project_ids = projects.where(public: false).pluck(:id)

      # All other users need to go through abilities
      ids = Authorization.service.subject_ids(
        actor: user.ability_delegate,
        subject_type: Project,
        subject_ids: available_project_ids,
        through: [Team, Organization],
      )

      projects.where(public: true).or(projects.where(id: ids))
    end
  end

  def writable_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.writable_projects_for", tags: ["owner_type:organization"]) do
      # Logged out users can't write to any projects.
      return Project.none if user.nil?

      # Bots with the correct permissions can write to all of the organization's
      # projects.
      return projects.scoped if user.can_have_granular_permissions? && resources.organization_projects.writable_by?(user.installation)

      # Org owners can write to all of the organization's projects
      return projects.scoped if adminable_by?(user)

      # All other users need to go through abilities
      ids = Authorization.service.subject_ids(
        actor: user.ability_delegate,
        subject_type: Project,
        through: [Team, Organization],
        actions: [:write, :admin],
      )

      projects.where(id: ids)
    end
  end
end
