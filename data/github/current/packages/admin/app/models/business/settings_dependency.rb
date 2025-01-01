# typed: true
# frozen_string_literal: true

module Business::SettingsDependency
  extend T::Helpers
  requires_ancestor { Business }

  TEAM_SYNC_TENANT_STATUS = {
    "PENDING" => TeamSync::Tenant.statuses[:pending],
    "FAILED" => TeamSync::Tenant.statuses[:failed],
    "READY" => TeamSync::Tenant.statuses[:ready],
    "ENABLED" => TeamSync::Tenant.statuses[:enabled],
    "DISABLED" => TeamSync::Tenant.statuses[:disabled],
  }.freeze
  SAML_PROVIDER_CONFIGURATION_STATES = {
    "ENFORCED" => "ENFORCED",
    "CONFIGURED" => "CONFIGURED",
    "UNCONFIGURED" => "UNCONFIGURED",
  }.freeze

  # Public: used to find organizations in the enterprise whose 2FA requirement is enabled or
  # disabled. A `value` of true returns organizations currently requiring 2FA, false the opposite.
  #
  # value: required - true or false, returns organizations with 2FA required or not required respectively
  # optional:
  # order_by_field: a `users` field used to order search results
  # order_by_direction: a direction to order search results
  #
  # Returns ActiveRecord::Relation
  def two_factor_required_organizations(value:, order_by_field: "login", order_by_direction: "ASC")
    orgs_for_boolean_setting_value(
      setting: Configurable::TwoFactorRequired::KEY,
      value: value,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: used to find organizations in the enterprise based on the state of their SAML Identity
  # provider situation.
  #
  # value: required - "ENFORCED", "CONFIGURED", or "UNCONFIGURED", returns organizations whose Provider
  #        configuration aligns with the argument
  # optional:
  # order_by_field: a `users` field used to order search results
  # order_by_direction: a direction to order search results
  #
  # Returns ActiveRecord::Relation
  def saml_configured_organizations(value:, order_by_field: "login", order_by_direction: "ASC")
    scope = if value == SAML_PROVIDER_CONFIGURATION_STATES["ENFORCED"]
      # Orgs with SAML SSO configured and enforced
      organizations.joins(:saml_provider).where(organization_saml_providers: { enforced: true })
    elsif value == SAML_PROVIDER_CONFIGURATION_STATES["CONFIGURED"]
      # Orgs with SAML SSO configured but not enforced
      organizations.joins(:saml_provider).where(organization_saml_providers: { enforced: false })
    elsif value == SAML_PROVIDER_CONFIGURATION_STATES["UNCONFIGURED"]
      # Orgs with SAML SSO unconfigured
      organizations.left_joins(:saml_provider).
        where(organization_saml_providers: { organization_id: nil })
    else
      raise ArgumentError, "Unexpected value: #{value}"
    end

    if order_by_field.present? && order_by_direction.present?
      scope = scope.order("users.#{order_by_field} #{order_by_direction}")
    end

    scope
  end

  # Public: used to find organizations in the enterprise based on the state of their Team Sync configuration
  # status. Only organizations whose tenant statuses are `PENDING`, `READY`, or `ENABLED` will be returned.
  #
  # Returns ActiveRecord::Relation
  def team_sync_enabled_orgs
    team_sync_statuses = [
      TEAM_SYNC_TENANT_STATUS["PENDING"],
      TEAM_SYNC_TENANT_STATUS["READY"],
      TEAM_SYNC_TENANT_STATUS["ENABLED"],
    ]
    organizations.with_team_sync_status(team_sync_statuses)
  end

  # Public: Used to find organizations in the enterprise whose private
  # repository forking value is enabled or disabled. A `value` of true returns
  # organizations with private repository forking enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def allow_private_repository_forking_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    map = org_id_to_setting_value_map(setting: Configurable::AllowPrivateRepositoryForking::KEY)

    org_ids = if value
      map.keep_if do |_id, val|
        !val.nil? && val != Configuration::FALSE
      end.keys
    else
      map.keep_if do |_id, val|
        val.nil? || val == Configuration::FALSE
      end.keys
    end

    ordered_orgs(org_ids: org_ids, order_by_field: order_by_field, order_by_direction: order_by_direction)
  end

  # Public: Used to find organizations in the enterprise whose repository
  # invitations setting value is enabled or disabled. A `value` of true returns
  # organizations with invitations enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_invite_collaborators_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanInviteOutsideCollaborators::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise whose members can change
  # repository visibility setting value is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_change_repository_visibility_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanChangeRepoVisibility::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise whose members can change
  # project visibility setting value is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_change_project_visibility_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanChangeProjectVisibility::KEY,
      value: value,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise whose members can delete
  # repositories is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_delete_repositories_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanDeleteRepositories::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise whose members can delete
  # issues in repositories is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_delete_issues_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanDeleteIssues::KEY,
      value: value,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise whose members can update
  # protected branch rules is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_update_protected_branches_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanUpdateProtectedBranches::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise where the team
  # discussions feature is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def team_discussions_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::DisableTeamDiscussions::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise where the organization
  # projects feature is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def organization_projects_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::DisableOrganizationProjects::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise where the repository
  # projects feature is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def repository_projects_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::DisableRepositoryProjects::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise where members can view
  # dependency insights is enabled or disabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_view_dependency_insights_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::MembersCanViewDependencyInsights::KEY,
      value: value,
      config_entry_value_reversed: true,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise with a specific default
  # repository permission setting.
  #
  # value: Required String, must be either: "read", "write", "admin", or "none".
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def default_repository_permission_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    map = org_id_to_setting_value_map(setting: Configurable::DefaultRepositoryPermission::KEY)
    org_ids = if value == "read"
      map.keep_if do |_id, val|
        val.nil?
      end.keys
    else
      map.keep_if do |_id, val|
        val == value
      end.keys
    end
    ordered_orgs(
      org_ids: org_ids,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise with a specific repository
  # creation setting.
  #
  # visibility: Required String, must be either: "PUBLIC", "PRIVATE", "INTERNAL", or "NONE"
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_create_repositories_organizations(
    visibility:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    map = org_id_to_setting_value_map(setting: Configurable::MembersCanCreateRepositories::KEY)

    if visibility == "NONE"
      org_ids = map.keep_if do |_id, val|
        Configurable::MembersCanCreateRepositories::ALL_ALIASES.include?(val)
      end.keys
    else
      # Need to invert the values since the internal setting controls which types of repositories users
      # are NOT allowed to create.
      disallowed_values = case visibility
      when "PUBLIC"
        Configurable::MembersCanCreateRepositories::PUBLIC_DISALLOWED_VALUES
      when "PRIVATE"
        Configurable::MembersCanCreateRepositories::PRIVATE_DISALLOWED_VALUES
      when "INTERNAL"
        Configurable::MembersCanCreateRepositories::INTERNAL_DISALLOWED_VALUES
      end
      org_ids = map.delete_if do |_id, val|
        disallowed_values.include?(val)
      end.keys
    end
    ordered_orgs(
      org_ids: org_ids,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise with a specific repository
  # creation setting.
  #
  # value: Required String, must be either: "ALL", "PRIVATE", "DISABLED"
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def members_can_create_repositories_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    # Need to invert the values since the internal setting controls which types of repositories users
    # are NOT allowed to create.
    map = org_id_to_setting_value_map(setting: Configurable::MembersCanCreateRepositories::KEY)
    org_ids = case value
    when "ALL"
      map.keep_if do |_id, val|
        val.nil? || val == Configurable::MembersCanCreateRepositories::NONE
      end.keys
    when "INTERNAL"
      map.keep_if do |_id, val|
        val == Configurable::MembersCanCreateRepositories::INTERNAL
      end.keys
    when "PRIVATE"
      map.keep_if do |_id, val|
        val == Configurable::MembersCanCreateRepositories::PUBLIC
      end.keys
    when "DISABLED"
      map.keep_if do |_id, val|
        val == Configurable::MembersCanCreateRepositories::ALL
      end.keys
    end
    ordered_orgs(
      org_ids: org_ids,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  # Public: Used to find organizations in the enterprise where restriction of email
  # notifications to eligible domain email is enabled. A `value` of true returns
  # organizations where enabled, false the opposite.
  #
  # value: Required Boolean, true for returning orgs with setting enabled, false otherwise
  # order_by_field: Optional String field used to order search results
  # order_by_direction: Optional String direction used to order search results
  #
  # Returns ActiveRecord::Relation
  def restrict_notification_delivery_setting_organizations(
    value:,
    order_by_field: "login",
    order_by_direction: "ASC"
  )
    orgs_for_boolean_setting_value(
      setting: Configurable::RestrictNotificationDelivery::KEY,
      value: value,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    )
  end

  private

  # Private: Return orgs within the enterprise account that match the given
  # boolean setting value, ordered when order_by is provided.
  #
  # setting - A String representing the name of the setting.
  # value - A String representing the value of the setting.
  # config_entry_value_reversed - A Boolean representing whether the
  #   config entry value is reversed. Set this to `true` if `value` is passed
  #   as `true` but the corresponding `configuration_entries` value is
  #   persisted as `nil` or `Configuration::FALSE`.
  # order_by_field - A field to use to order the returned organizations
  # order_by_direction — A direction to order the returned organizations
  #
  # Returns ActiveRecord::Relation.
  def orgs_for_boolean_setting_value(
    setting:,
    value:,
    config_entry_value_reversed: false,
    order_by_direction: "ASC",
    order_by_field: "login"
  )
    map = org_id_to_setting_value_map(setting: setting)
    org_ids = if config_entry_value_reversed
      if value
        map.keep_if do |_id, val|
          val.nil? || val == Configuration::FALSE
        end.keys
      else
        map.keep_if do |_id, val|
          val == Configuration::TRUE
        end.keys
      end
    else
      if value
        map.keep_if do |_id, val|
          val == Configuration::TRUE
        end.keys
      else
        map.keep_if do |_id, val|
          val.nil? || val == Configuration::FALSE
        end.keys
      end
    end
    ordered_orgs(org_ids: org_ids, order_by_field: order_by_field, order_by_direction: order_by_direction)
  end

  # Private: Get a Hash that maps org IDs to the value for the given
  # enterprise setting.
  #
  # Example of the Hash returned for the enterprise account:
  #
  # {
  #   18787: nil,
  #   34341: "true"
  #   28484: "false"
  # }
  #
  # setting - A String representing the name of the setting.
  #
  # Returns Hash.
  def org_id_to_setting_value_map(setting:)
    entries = []
    # Batch queries to cater for a large number of orgs in an enterprise
    organization_ids.each_slice(5_000) do |slice|
      entries.concat Configuration::Entry
        .named(setting)
        .targeting_user_ids(slice)
        .pluck(:target_id, :value)
    end

    # Map org IDs to setting value
    {}.tap do |map|
      organization_ids.each { |id| map[id] = nil }
      entries.each { |entry| map[entry.first] = entry.second }
    end
  end

  # Private: Return orgs matching the provided IDs, ordered when provided
  #
  # org_ids - Array of Integer representing org IDs.
  # order_by_field - String field to order organizations by. Default "login".
  # order_by_direction - String direction to order organizations. Default "ASC".
  #
  # Returns ActiveRecord::Relation.
  def ordered_orgs(org_ids:, order_by_field: "login", order_by_direction: "ASC")
    scope = ::Organization.where(id: org_ids)
    scope = scope.order("users.#{order_by_field} #{order_by_direction}") if order_by_field && order_by_direction
    scope
  end
end
