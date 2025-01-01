# typed: true
# frozen_string_literal: true

module Organization::PermissionsDependency
  extend T::Sig


  AuthzdActor = T.type_alias do
    T.any(
      User,
      OrganizationProgrammaticAccessGrant,
      UserProgrammaticAccessGrant,
      IntegrationInstallation,
      ScopedIntegrationInstallation,
      SiteScopedIntegrationInstallation)
  end

  include IntegrationManagerHelper
  include GitHub::Memoizer

  def async_can_access_custom_repo_roles?(user, action)
    case action
    when :read
      async_can_read_custom_repo_roles?(user)
    when :write
      async_can_write_custom_repo_roles?(user)
    else
      Promise.resolve(false)
    end
  end

  def async_can_read_custom_repo_roles?(user)
    return Promise.resolve(false) unless user
    async_authorized_via_policy?(user, :read_organization_custom_repo_role)
  end

  def async_can_write_custom_repo_roles?(user)
    return Promise.resolve(false) unless user
    async_authorized_via_policy?(user, :write_organization_custom_repo_role)
  end

  def async_can_access_custom_org_roles?(user, action)
    case action
    when :read
      async_can_read_custom_org_roles?(user)
    when :write
      async_can_write_custom_org_roles?(user)
    else
      Promise.resolve(false)
    end
  end

  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_read_custom_org_roles?(user)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless user
    async_authorized_via_policy?(user, :read_organization_custom_org_role)
  end

  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_write_custom_org_roles?(user)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless user
    async_authorized_via_policy?(user, :write_organization_custom_org_role)
  end

  sig { params(user: T.nilable(User), site_admin: T.nilable(T::Boolean)).returns(T::Boolean) }
  def can_write_org_webhooks?(user, site_admin: false)
    async_can_write_org_webhooks?(user, site_admin: site_admin).sync
  end

  sig { params(actor: T.nilable(AuthzdActor), site_admin: T.nilable(T::Boolean)).returns(Promise[T::Boolean]) }
  def async_can_write_org_webhooks?(actor, site_admin: false)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :manage_organization_webhooks, { "action.programmatic_access_level": Permission.actions[:write], considers_site_admin: site_admin })
  end

  sig { params(user: T.nilable(User), site_admin: T.nilable(T::Boolean)).returns(T::Boolean) }
  def can_read_org_webhooks?(user, site_admin: false)
    async_can_read_org_webhooks?(user, site_admin: site_admin).sync
  end

  sig { params(actor: T.nilable(AuthzdActor), site_admin: T.nilable(T::Boolean)).returns(Promise[T::Boolean]) }
  def async_can_read_org_webhooks?(actor, site_admin: false)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :manage_organization_webhooks, { "action.programmatic_access_level": Permission.actions[:read], considers_site_admin: site_admin })
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_manage_org_oauth_app_policy?(user)
    async_can_manage_org_oauth_app_policy?(user).sync
  end

  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_manage_org_oauth_app_policy?(user)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless user
    async_authorized_via_policy?(user, :manage_organization_oauth_application_policy)
  end

  # Public: Which settings can a user access for a repository?
  #
  # user - The User to get the permissions for
  #
  # Returns a Hash
  sig { params(user: T.nilable(User)).returns(T::Hash[T.untyped, T.untyped]) }
  def org_settings_permissions_hash(user)
    T.bind(self, Organization)
    # shortcut for anonymous requests
    unless user.present?
      return Hash.new
    end
    return @org_settings_permissions_hash[user] if defined?(@org_settings_permissions_hash) && !@org_settings_permissions_hash[user].nil?
    unless defined?(@org_settings_permissions_hash)
      @org_settings_permissions_hash = Hash.new
    end

    billing_manager,
    moderator,
    app_manager,
    code_security,
    ref_rules_manager,
    custom_properties_definitions_manager,
    custom_properties_values_editor,
    view_org_setting = Promise.all([
      async_billing_manager?(user),
      async_moderator?(user),
      async_manages_any_integration?(user: user, organization: self),
      SecurityProduct::Permissions::OrgAuthz.new(self, actor: user).async_can_manage_security_products?,
      async_can_manage_organization_ref_rules?(user),
      async_can_manage_organization_custom_properties_definitions?(user),
      async_can_edit_organization_custom_properties_values?(user),
      async_has_organization_setting_fgp?(user)
    ]).sync

    @org_settings_permissions_hash[user] = {
      is_billing_manager: billing_manager,
      is_moderator: moderator,
      is_app_manager: app_manager,
      is_code_security_manager: code_security,
      is_ref_rules_manager: ref_rules_manager,
      is_custom_properties_definitions_manager: custom_properties_definitions_manager,
      is_custom_properties_values_editor: custom_properties_values_editor,
      can_view_org_setting: view_org_setting
    }
  end

  # Public: Can a user access one or more organization settings options?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_view_organization_settings?(user)
    T.bind(self, Organization)
    return false unless user.present?
    return true if self.adminable_by?(user)
    org_settings_permissions_hash(user).values.any?
  end

  sig { params(user: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_read_org_audit_logs?(user)
    async_can_read_org_audit_logs?(user).sync
  end

  # Check to see if the user satisfies the read_audit_logs Authzd policy
  sig { params(user: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_read_org_audit_logs?(user)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless user
    async_authorized_via_policy?(user, :read_audit_logs)
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_manage_organization_ref_rules?(actor)
    async_can_manage_organization_ref_rules?(actor).sync
  end

  # Check to see if the user satisfies the manage_organization_ref_rules Authzd policy
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_manage_organization_ref_rules?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor

    # TODO: Support integrations in the authz policy
    if actor.is_a?(User) && !actor.try(:can_have_granular_permissions?)
      async_authorized_via_policy?(actor, :manage_organization_ref_rules)
    else
      Promise.resolve(self.resources.organization_administration.writable_by?(actor))
    end
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_manage_organization_custom_properties_definitions?(actor)
    async_can_manage_organization_custom_properties_definitions?(actor).sync
  end

  # Check to see if the user satisfies the manage_org_custom_properties_definitions Authzd policy
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_manage_organization_custom_properties_definitions?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor

    # temporary until new permissions are published
    if actor.is_a?(User) && !actor.try(:can_have_granular_permissions?)
      async_authorized_via_policy?(actor, :manage_org_custom_properties_definitions)
    else
      # the org admin check is deprecated
      Promise.resolve(self.resources.organization_custom_properties.adminable_by?(actor) || self.resources.organization_administration.writable_by?(actor))
    end

    # long-term code:
    # async_authorized_via_policy?(actor, :manage_org_custom_properties_definitions, { "action.programmatic_access_level": Permission.actions[:admin] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_edit_organization_custom_properties_values?(actor)
    async_can_edit_organization_custom_properties_values?(actor).sync
  end

  # Check to see if the user satisfies the edit_org_custom_properties_values Authzd policy
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_edit_organization_custom_properties_values?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor

    # temporary until new permissions are published
    if actor.is_a?(User) && !actor.try(:can_have_granular_permissions?)
      async_authorized_via_policy?(actor, :edit_org_custom_properties_values)
    else
      # the org admin check is deprecated
      Promise.resolve(self.resources.organization_custom_properties.writable_by?(actor) || self.resources.organization_administration.writable_by?(actor))
    end

    # long-term code:
    # async_authorized_via_policy?(actor, :edit_org_custom_properties_values, { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_actions_settings?(actor)
    async_can_write_organization_actions_settings?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_actions_settings Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_actions_settings?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_actions_settings,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_actions_variables?(actor)
    async_can_write_organization_actions_variables?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_variables Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_actions_variables?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_actions_variables,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_actions_secrets?(actor)
    async_can_write_organization_actions_secrets?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_secrets Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_actions_secrets?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_actions_secrets,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_runners_and_runner_groups?(actor)
    async_can_write_organization_runners_and_runner_groups?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_runners_and_runner_groups Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_runners_and_runner_groups?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_runners_and_runner_groups,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_network_configurations?(actor)
    async_can_write_organization_network_configurations?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_network_configurations Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_network_configurations?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_network_configurations,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_read_organization_network_configurations?(actor)
    async_can_read_organization_network_configurations?(actor).sync
  end

  # Check to see if the user satisfies the read_organization_network_configurations Authzd policy with read access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_read_organization_network_configurations?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :read_organization_network_configurations,
      { "action.programmatic_access_level": Permission.actions[:read] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_write_organization_packages?(actor)
    async_can_write_organization_packages?(actor).sync
  end

  # Check to see if the user satisfies the write_organization_packages Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_write_organization_packages?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :write_organization_packages,
      { "action.programmatic_access_level": Permission.actions[:write] })
  end

  sig { params(actor: T.nilable(AuthzdActor)).returns(T::Boolean) }
  def can_read_organization_actions_usage_metrics?(actor)
    async_can_read_organization_actions_usage_metrics?(actor).sync
  end

  # Check to see if the user satisfies the read_organization_actions_usage_metrics Authzd policy with write access
  sig { params(actor: T.nilable(AuthzdActor)).returns(Promise[T::Boolean]) }
  def async_can_read_organization_actions_usage_metrics?(actor)
    T.bind(self, Organization)

    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor
    async_authorized_via_policy?(actor, :read_organization_actions_usage_metrics)
  end

  # Check if user has FGP to view API Insights Dashboard
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_view_org_api_insights?(user)
    T.bind(self, Organization)
    return Promise.resolve(T.cast(false, T::Boolean)) unless user
    return Promise.resolve(T.cast(true, T::Boolean)) if self.adminable_by?(user)
    async_authorized_via_policy?(user, :view_org_api_insights)
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_view_org_api_insights?(user)
    async_can_view_org_api_insights?(user).sync
  end

  private

  # Internal: Generic method to check if a user is authorized via an authzd policy
  sig { params(actor: AuthzdActor, action: Symbol, context: T::Hash[T.untyped, T.untyped]).returns(Promise[T::Boolean]) }
  def async_authorized_via_policy?(actor, action, context = {})
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: action,
      actor: actor,
      subject: self,
      context: context
    ).then do |result|
      result.allow?
    end
  end

  # Internal: method to check if a user is authorized to view any Organization Setting via an authzd policy
  sig { params(user: User).returns(Promise[T::Boolean]) }
  def async_has_organization_setting_fgp?(user)
    T.bind(self, Organization)

    organization_settings = []
    organization_settings << :read_audit_logs
    organization_settings << :manage_organization_webhooks
    organization_settings << :manage_organization_oauth_application_policy
    organization_settings << :manage_organization_ref_rules
    organization_settings << :read_organization_custom_org_role
    organization_settings << :write_organization_custom_org_role
    organization_settings << :read_organization_custom_repo_role
    organization_settings << :write_organization_custom_repo_role
    organization_settings << :write_organization_actions_settings
    organization_settings << :write_organization_actions_secrets
    organization_settings << :write_organization_actions_variables
    organization_settings << :write_organization_runners_and_runner_groups
    organization_settings << :read_organization_actions_usage_metrics if self.actions_usage_metrics_enabled?(user)
    organization_settings << :manage_org_custom_properties_definitions
    organization_settings << :edit_org_custom_properties_values

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :manage_any_org_setting,
      actor: user,
      subject: self,
      context: {
        "organization.fine_grained_permissions": organization_settings
      }
    ).then do |result|
      result.allow?
    end
  end
end
