# typed: true
# frozen_string_literal: true

module MemexProject::PermissionsDependency
  extend T::Helpers
  requires_ancestor { MemexProject }

  def async_viewer_can_update?(viewer)
    async_viewer_can_write?(viewer)
  end

  def async_readable_by_bot?(bot)
    async_owner.then do |owner|
      next false unless owner.present?

      owner.projects_readable_by?(bot)
    end
  end

  def async_readable_by?(viewer)
    actor = viewer.try(:installation) || viewer
    if actor&.can_have_granular_permissions?
      return async_readable_by_bot?(actor)
    end

    async_viewer_can_read?(viewer)
  end

  def readable_by?(viewer, organization = nil)
    async_readable_by?(viewer).sync
  end

  def viewer_can_read?(viewer)
    async_viewer_can_read?(viewer).sync
  end

  def viewer_can_write?(viewer)
    async_viewer_can_write?(viewer).sync
  end

  def viewer_is_admin?(viewer)
    Permissions::Enforcer.authorize(**T.unsafe(admin_authzd_request(viewer))).allow?
  end

  def viewer_can_change_visibility?(viewer)
    Permissions::Enforcer
      .authorize(**T.unsafe(change_visibility_authzd_request(viewer, {})))
      .allow?
  end

  def viewer_most_capable_permission(viewer)
    requests = [
      admin_authzd_request(viewer),
      writer_authzd_request(viewer),
      reader_authzd_request(viewer, {})
    ]
    responses_by_request = Permissions::Enforcer.batch_authorize(requests: requests)

    return :admin if responses_by_request[requests[0]].allow?
    return :write if responses_by_request[requests[1]].allow?
    return :read if responses_by_request[requests[2]].allow?
    :none
  end

  def async_viewer_most_capable_permission(viewer)
    permissions_checks = [
      async_viewer_is_admin?(viewer),
      async_viewer_can_write?(viewer),
      async_viewer_can_read?(viewer),
    ]
    async_permissions = Promise.all(permissions_checks).then do |results|
      # Hashes enumerate their values in the order that the corresponding keys were inserted. So, first available will be the most capable.
      # https://ruby-doc.org/core-2.2.2/Hash.html

      granted_permissions = {
        admin: results[0],
        write: results[1],
        read: results[2],
      }.select { |_k, v| v }.keys

      next :none if granted_permissions.empty?

      granted_permissions.first
    end
  end

  # Whether the viewer has read access to the Memex Project. Note that this could be false even if the project is "public".
  #
  # A "public" project that is owned by an org or user within an enterprise with Enterprise Managed Users (EMU)
  # should actually be considered "internal" (i.e., visible only to members of the enterprise, not to the world).
  def async_viewer_can_read?(viewer)
    return Promise.resolve(false) if async_user_project_bot_access?(viewer).sync

    Platform::Loaders::Permissions::BatchAuthorize
      .load(**T.unsafe(reader_authzd_request(viewer, {})))
      .then(&:allow?)
  end

  def async_viewer_can_write?(viewer)
    return Promise.resolve(false) if async_user_project_bot_access?(viewer).sync

    Platform::Loaders::Permissions::BatchAuthorize.load(**T.unsafe(writer_authzd_request(viewer))).then(&:allow?)
  end

  # Determines if the project is user-owned and the viewer is a bot. This is used to prevent
  # unecessary calls to authzd, since bots cannot access user-owned projects. Typically, this
  # would be handled by an authzd policy, but we want to avoid the overhead of making that call
  # when it's an known value.
  def async_user_project_bot_access?(viewer)
    async_owner.then do |owner|
      owner&.user? && viewer&.can_have_granular_permissions?
    end
  end

  # If a user can write to a project, they can close/reopen it.
  alias :async_closable_by? :async_viewer_can_write?
  alias :async_reopenable_by? :async_viewer_can_write?

  def async_viewer_is_admin?(viewer)
    Platform::Loaders::Permissions::BatchAuthorize.load(**T.unsafe(admin_authzd_request(viewer))).then(&:allow?)
  end

  def async_viewer_can_change_visibility?(viewer)
    Platform::Loaders::Permissions::BatchAuthorize
      .load(**T.unsafe(change_visibility_authzd_request(viewer, {})))
      .then(&:allow?)
  end

  def organization_wide_role
    # This query logic is following the same logic Authzd uses to check org level access:
    # Link to Authzd attribute resolver: https://github.com/github/authzd/blob/master/config/attributes/subject.memex_project.roles.organization_members.sql
    # It's unlikely for Authzd logic to change but we need to keep both queries in sync.
    result = ::Configuration::Entry.connection.select_values(Arel.sql(<<~SQL, memex_id: id, organization_id: owner_id, name: MemexProject::ORGANIZATION_WIDE_ROLE_CONFIG_KEY))
      SELECT
        value,
        CASE target_type
        WHEN 'global'       THEN 3
        WHEN 'User'         THEN 2
        WHEN 'MemexProject' THEN 1
        END AS priority
      FROM configuration_entries
      WHERE
        name = :name AND final = 0 AND (
          (target_id = :memex_id AND target_type = "MemexProject") OR
          (target_id = :organization_id AND target_type = "User") OR
          target_type = "global")
      ORDER BY priority LIMIT 1
    SQL

    result.length == 0 ? "none" : result[0]
  end

  # Updates an org-wide role
  #
  # role: The name of the role to grant. Only project roles are allowed (project_reader, project_writer, project_admin).
  # updater: User who is making the change.
  def update_organization_wide_role(role, updater)
    return unless owner.organization?

    role_to_grant = role.to_s
    unless [Role::MEMEX_PROJECTS_SYSTEM_ROLES, "none"].flatten.include?(role_to_grant)
      raise ArgumentError, "Invalid role name: #{role_to_grant}"
    end

    config_entry = ::Configuration::Entry.memex_project_org_wide_role
      .targeting_memex_projects
      .for_target_id(id)
      .take


    old_base_role = "none"

    if config_entry.present?
      old_base_role = config_entry.value
      config_entry.update(value: role_to_grant)
    else
      ::Configuration::Entry.targeting_memex_projects
        .memex_project_org_wide_role
        .for_target_id(id)
        .with_value(role_to_grant)
        .create!(updater: updater)
    end

    GitHub.instrument("project_base_role.update", {
      old_project_base_role: old_base_role,
      new_project_base_role: role_to_grant,
      project: self,
      project_number: self&.number,
      public_project: self&.public?,
      org: owner,
      business: owner.business
    })

  end

  def async_accessible(viewer, min_permission_level = "read")
    async_accessible = case min_permission_level.to_s
    when "read"
      async_viewer_can_read?(viewer)
    when "write"
      async_viewer_can_write?(viewer)
    when "admin"
      async_viewer_is_admin?(viewer)
    else
      raise "Unsupported permissions: #{min_permission_level}"
    end

    async_accessible
  end

  # Grants a role to a project.
  #
  # actor: User or Team that is being granted the role.
  # role_or_name: Instance of the Role or the name of the role to grant. Only project roles
  #               are allowed (project_reader, project_writer, project_admin)
  #               or short version (reader, writer, admin).
  def grant_role(actor, role_or_name)
    role = sanitize_role(role_or_name)
    Permissions::Granters::RoleGranter.new(
      actor: actor, target: self, role: role
    ).grant_unless_exists!
  end

  # Revokes actor's role from a project.
  #
  # actor: User or Team, whose role is being revoked.
  # role_or_name: Instance of the Role or the name of the role to grant. Only project roles
  #               are allowed (project_reader, project_writer, project_admin)
  #               or short version (reader, writer, admin).
  def revoke_role(actor, role_or_name)
    role = sanitize_role(role_or_name)
    Permissions::Granters::RoleGranter.new(
      actor: actor, target: self, role: role
    ).revoke_if_exists!
  end

  def view_live_update_authzd_attributes
    {
      version: Permissions::PolicyVersion.version_for(
        action: :view_live_update,
        subject: T.cast(self, MemexProject)
      )
    }
  end

  # Returns a promise containing all the enterprise/business-related attributes for this MemexProject.
  #
  # The promises in this method  are grouped together because internally they reuse many of the same sub-promises,
  # so we get better cache efficiency by resolving them together.
  sig { returns(Promise[T::Hash[T.untyped, T.untyped]]) }
  def async_enterprise_authzd_attributes
    Promise.all([async_owner_is_enterprise_managed?, async_business]).then do |owner_is_enterprise_managed, business|
      {
        "subject.owner.enterprise_managed" => owner_is_enterprise_managed,
        "subject.business.id" => business&.id,
      }
    end
  end

  private

  def sanitize_role(role_or_name)
    if role_or_name.is_a?(Role)
      raise ArgumentError, "Not a project role: #{role_or_name.name}" unless Role::MEMEX_PROJECTS_SYSTEM_ROLES.include?(role_or_name.name)
      role_or_name
    else
      # It is possible to pass 'project_writer' as well as 'writer' as argument
      role_name = role_or_name.start_with?("project_") ? role_or_name : "project_#{role_or_name}"
      role = Role.internal_role_by_name(role_name)
      raise ArgumentError, "Invalid role name: #{role_or_name}" unless Role::MEMEX_PROJECTS_SYSTEM_ROLES.include?(role&.name)
      role
    end
  end

  sig do
    params(
      viewer: T.nilable(T.any(User, IntegrationInstallation)),
      context: T::Hash[T.untyped, T.untyped]
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def reader_authzd_request(viewer, context)
    {
      action: :read_project,
      actor: viewer,
      subject: self,
      context: { "considers_anonymous" => true }.merge(context)
    }
  end

  sig do
    params(
      viewer: T.nilable(T.any(User, IntegrationInstallation)),
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def writer_authzd_request(viewer)
    {
      action: :write_project,
      actor: viewer,
      subject: self,
    }
  end

  sig do
    params(
      viewer: T.nilable(T.any(User, IntegrationInstallation)),
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def admin_authzd_request(viewer)
    {
      action: :admin_project,
      actor: viewer,
      subject: self,
    }
  end

  sig do
    params(
      viewer: T.nilable(User),
      context: T::Hash[T.untyped, T.untyped]
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def change_visibility_authzd_request(viewer, context)
    {
      action: :change_project_visibility,
      actor: viewer,
      subject: self,
      context:
    }
  end
end
