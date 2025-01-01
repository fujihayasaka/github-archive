# typed: false
# frozen_string_literal: true

module Repository::ProjectsDependency
  extend ActiveSupport::Concern

  include Configurable::DisableRepositoryProjects

  class CannotEnableProjectsError < StandardError; end

  included do
    alias_method :projects_enabled?, :repository_projects_enabled?
    alias_method :async_projects_enabled?, :async_repository_projects_enabled?

    def self.filter_ids_with_projects_enabled(ids)
      repo_ids = ids.dup

      # Filter repos where projects disabled
      disabled_projects_repo_ids = Configuration::Entry.with_true_value
        .named(Configurable::DisableRepositoryProjects::KEY)
        .targeting_repository_ids(repo_ids)
        .pluck(:target_id)

      relevant_repo_ids = repo_ids - disabled_projects_repo_ids
      return relevant_repo_ids if relevant_repo_ids.empty?

      # Filter repos where org owner has repository projects disabled
      org_owned_repos_by_owner_id = Hash.new { |h, k| h[k] = [] }
      org_owned_repos = Repository.where(id: relevant_repo_ids).org_owned.pluck(:owner_id, :id)
      org_owned_repos.each do |owner_id, id|
        org_owned_repos_by_owner_id[owner_id] << id
      end

      disabled_projects_org_ids = Configuration::Entry.with_true_value
        .named(Configurable::DisableRepositoryProjects::KEY)
        .targeting_user_ids(org_owned_repos_by_owner_id.keys)
        .pluck(:target_id)

      relevant_repo_ids -= disabled_projects_org_ids.flat_map { |org_id| org_owned_repos_by_owner_id[org_id] }

      relevant_repo_ids
    end
  end

  # Public: Can projects be enabled for this repository?
  #
  # Returns a Boolean.
  def can_enable_projects?
    async_can_enable_projects?.sync
  end

  # Public: Can projects be enabled for this repository?
  #
  # Returns a Promise<Boolean>.
  def async_can_enable_projects?
    async_owner.then do |owner|
      next true unless owner.organization?
      owner.async_repository_projects_enabled?
    end
  end

  def enable_repository_projects(**arguments)
    ensure_projects_can_be_enabled!
    super
  end

  def has_any_projects?
    self.projects.any?
  end

  def has_repository_projects=(new_value)
    set_has_repository_projects(new_value)
  end

  def set_has_repository_projects(new_value)
    ensure_projects_can_be_enabled! if new_value
    @has_repository_projects = new_value
  end

  def visible_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.visible_projects_for", tags: ["owner_type:repository"]) do
      # Since repository-owned projects inherit permissions from their owning
      # repository, we don't have to do any extra abilities checks here.
      if (user&.can_have_granular_permissions? && projects_readable_by?(user)) || readable_by?(user)
        projects
      else
        Project.none
      end
    end
  end

  def writable_projects_for(user)
    GitHub.dogstats.distribution_time("project_permissions.dist.writable_projects_for", tags: ["owner_type:repository"]) do
      # Since repository-owned projects inherit permissions from their owning
      # repository, we don't have to do any extra abilities checks here.
      if (user&.can_have_granular_permissions? && projects_writable_by?(user)) || writable_by?(user)
        projects
      else
        Project.none
      end
    end
  end

  private def ensure_projects_can_be_enabled
    if @has_repository_projects && !can_enable_projects?
      errors.add(:has_projects, "can't be enabled because the owning organization has repository projects disabled.")
    end
  end

  private def ensure_projects_can_be_enabled!
    raise CannotEnableProjectsError unless can_enable_projects?
  end

  # Internal: Correct any issue cards associated with organization-owned
  # projects since cards can only be associated with issues in repositories that
  # are in the organization.
  #
  # For public repositories the issue cards are converted to issue note
  # references linking to the new issue URLs.
  #
  # For private repositories the issue cards are removed from the project.
  def correct_project_cards(old_owner:)
    return unless old_owner.respond_to?(:projects)

    issue_ids = issues.pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    card_action_sym = public? ? :convert_to_note_reference! : :destroy
    moving_project_ids = MoveWorkItem.started_for_owner(old_owner).projects.pluck(:resource_id)

    old_owner.projects.where.not(id: moving_project_ids).find_each do |project|
      project.cards.
        for_content_type("Issue").
        where(content_id: issue_ids).
        find_each(&card_action_sym)
    end
  end

  # Public: Can the specified actor view projects on this organization?
  #
  # actor - The User trying to view projects.
  #
  # Returns a boolean.
  def projects_readable_by?(actor)
    resources.repository_projects.readable_by?(actor)
  end

  # Public: Can the specified actor view projects on this organization?
  #
  # actor - The User trying to view projects.
  #
  # Returns Promise<bool>
  def async_projects_readable_by?(actor)
    resources.repository_projects.async_readable_by?(actor)
  end

  # Public: Can the specified actor create/edit projects on this repository?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns a boolean.
  def projects_writable_by?(actor)
    resources.repository_projects.writable_by?(actor)
  end

  # Public: Can the specified actor create/edit projects on this repository?
  #
  # actor - The User trying to create/edit projects.
  #
  # Returns Promise<bool>
  def async_projects_writable_by?(actor)
    resources.repository_projects.async_writable_by?(actor)
  end

  # Public: Can the specified actor administer projects on this repository?
  #
  # actor - The User trying to administer projects.
  #
  # Returns a boolean.
  def projects_adminable_by?(actor)
    # We intentionally use writable_by? here, since there's no concept of
    # admin on projects in the pre-Abilities permission system.
    projects_writable_by?(actor)
  end

  # Public: Can the specified actor administer projects on this repository?
  #
  # actor - The User trying to administer projects.
  #
  # Returns Promise<bool>
  def async_projects_adminable_by?(actor)
    # We intentionally use writable_by? here, since there's no concept of
    # admin on projects in the pre-Abilities permission system.
    async_projects_writable_by?(actor)
  end
end
