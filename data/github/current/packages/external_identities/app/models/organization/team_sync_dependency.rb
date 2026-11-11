# typed: false
# frozen_string_literal: true

module Organization::TeamSyncDependency

  # Public: Whether the Organization can configure Team Sync or not.
  #
  # Returns a Boolean.
  def team_sync_feature_available?
    return false if GitHub.enterprise?
    return false if business&.enterprise_managed_user_enabled?
    return false unless business_plus?
    saml_sso_setup?
  end

  # Public: Whether the Organization has configured and enabled Team Sync.
  #
  # Returns a Boolean.
  def team_sync_enabled?
    return false unless team_sync_feature_available?

    !!team_sync_tenant&.enabled?
  end
  alias_method :show_team_sync_feature?, :team_sync_enabled?

  # Public: Whether Organization has configured and enabled Team Sync.
  #
  # It differs from its non-async counterpart by not relying on the External
  # Identity Session (that is, not using saml_sso_setup?) in order to support
  # organizations that get team sync through their businesses.
  #
  # Returns a Promise that resolves to a Boolean.
  def async_team_sync_enabled?
    return Promise.resolve(false) if GitHub.enterprise?

    async_business.then do |business|
      if !business&.enterprise_managed_user_enabled? && business&.team_sync_enabled?
        team_sync_enabled?
      else
        async_saml_provider.then do
          next false unless saml_sso_enabled?
          async_team_sync_tenant.then do |team_sync_tenant|
            !!team_sync_tenant&.enabled?
          end
        end
      end
    end
  end

  # Public: Returns the teams that are externally managed via Team Sync
  #
  # Returns a Promise that resolves to scope
  def async_externally_managed_teams
    async_team_sync_enabled?.then do |enabled|
      next Team.none unless enabled
      async_externally_managed_team_ids.then do |ids|
        teams.where(id: ids)
      end
    end
  end

  # Public: Returns the team ids that are externally managed via Team Sync
  #
  # Returns a Promise that resolves to an Array
  def async_externally_managed_team_ids
    async_team_sync_enabled?.then do |enabled|
      next [] unless enabled
      async_team_sync_tenant.then do |tenant|
        tenant.team_group_mappings.distinct.pluck(:team_id)
      end
    end
  end

  # Internal: Returns a boolean value to determine if an organization has a tenant object
  def has_team_sync_tenant?
    !team_sync_tenant.nil?
  end

  # Internal: Returns a boolean value to determine if SAML SSO is setup using the
  # External Identity Session Owner object. The object here can either be an Organization
  # or a Business; the external_identity_session_owner will internally take care of that
  # distinction.
  def saml_sso_setup?
    saml_provider = external_identity_session_owner.saml_provider
    saml_provider.present? && saml_provider.persisted?
  end

  def team_sync_failed?
    team_sync_tenant&.team_group_mappings&.failed&.exists?
  end

  def team_sync_failed_teams
    failed_team_ids = team_sync_tenant&.team_group_mappings&.failed&.distinct&.pluck(:team_id)
    Team.where(id: failed_team_ids)
  end
end
