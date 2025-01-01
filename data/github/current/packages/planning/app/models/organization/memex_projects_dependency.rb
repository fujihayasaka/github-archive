# typed: true
# frozen_string_literal: true

module Organization::MemexProjectsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { Organization }

  include MemexProject::SharedMemexProjectsDependency
  include Instrumentation::Model

  included do
    T.bind(self, T.class_of(Organization))
    # rubocop:todo Rails/InverseOf
    has_many :memex_project_links, -> { where(source_type: "Organization") }, foreign_key: :source_id, dependent: :destroy
    # rubocop:enable Rails/InverseOf
  end

  # Checks accessibility of memexes in a search scope using Authzd Batch Authorization and returns the scope that will query only accessible memexes
  # Parameters:
  #   search_scope - scope of the query that lists Memex Projects
  #   user - user viewing list of projects
  #   min_permissions_level - level of permissions we want to check for. Possible values: read, write, admin
  #   auth_method - method to use for checking permissions. Possible values: enumeration & batching.
  #   filter_ids - only return the ids of the accessible projects that intersect with the filter ids
  def accessible_memexes_scope(search_scope, user, min_permission_level = "read", auth_method = :enumeration, filter_ids: [])
    async_accessible_memexes_scope(search_scope, user, min_permission_level, auth_method, filter_ids: filter_ids).sync
  end

  def async_accessible_memexes_scope(search_scope, user, min_permission_level = "read", auth_method = :enumeration, filter_ids: [])
    search_scope = search_scope.active_projects.filter_spam_for(user)

    # GitHub apps currently are not supported for the enumeration method, so we must use
    # batching to fetch the permissions here, regardless of which method was requested.
    # see: https://github.com/github/authorization/issues/2899
    if user.is_a?(Bot)
      auth_method = :batching
    end

    if auth_method == :enumeration
      Promise.resolve(accessible_memexes_scope_using_enumeration(search_scope, user, min_permission_level, filter_ids: filter_ids))
    elsif auth_method == :batching
      async_accessible_memexes_scope_using_batching(search_scope, user, min_permission_level, filter_ids: filter_ids).then do |accessible_memexes|
        accessible_memexes
      end
    else
      raise "Unknown auth method: #{auth_method}"
    end
  end

  def projects_base_role
    config_entry = ::Configuration::Entry.memex_project_org_wide_role
    .targeting_users
    .for_target_id(id)
    .take&.value

    config_entry ||= ::Configuration::Entry.memex_project_org_wide_role.global.take&.value
    config_entry ||= "none"
  end

  # Updates an org-wide projects permission role
  #
  # role: The name of the role to grant. Only project roles are allowed (project_reader, project_writer, project_admin, none).
  # updater: User who is making the change.
  def update_organization_wide_projects_role(role, updater)
    raise ArgumentError unless adminable_by?(updater)

    unless [Role::MEMEX_PROJECTS_SYSTEM_ROLES, "none"].flatten.include?(role)
      raise ArgumentError, "Invalid role name: #{role}"
    end

    old_base_role = "none"

    config_entry = ::Configuration::Entry.memex_project_org_wide_role
      .targeting_users
      .for_target_id(id)
      .take

    if config_entry.present?
      old_base_role = config_entry.value
      config_entry.update(value: role)
    else
      ::Configuration::Entry.memex_project_org_wide_role
        .targeting_users
        .for_target_id(id)
        .with_value(role)
        .create!(updater: updater)
    end

    GitHub.instrument("organization_wide_project_base_role.update", {
      old_project_base_role: old_base_role,
      new_project_base_role: role,
      org: self,
      business: self.business
    })
  end

  def projects_without_base_role_set_count
    return @projects_without_base_role_set_count if defined?(@projects_without_base_role_set_count)

    @projects_without_base_role_set_count = begin
      org_projects = memex_projects.pluck(:id)
      return 0 if org_projects.empty?
      projects_with_base_role_set = ::Configuration::Entry.memex_project_org_wide_role.targeting_memex_projects.for_target_id(org_projects)
      org_projects.count - projects_with_base_role_set.count
    end
  end

  # Used to limit search results to only repos with a specific milestone in the context
  # of a grouping by milestone.
  # Since the repository_ids array is not upper-bound, perform the query in batches.
  sig { params(milestone_title: String).returns(T::Array[Integer]) }
  def repo_ids_with_milestone(milestone_title)
    repository_ids = repositories.ids
    Milestone.batched_scope(:repository_id, values: repository_ids).where(title: milestone_title).pluck(:repository_id)
  end

  private

  def accessible_memexes_scope_using_batching(search_scope, user, min_permission_level, filter_ids: [])
    async_accessible_memexes_scope_using_batching(search_scope, user, min_permission_level, filter_ids: filter_ids).sync
  end
end
