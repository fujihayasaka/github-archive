# typed: false
# frozen_string_literal: true

# Tracking external Identity Provider dependencies for a business. Supports both SAML and OIDC
module Business::ExternalProviderDependency
  extend ActiveSupport::Concern

  include Business::ExternalProviderMembers

  MAX_RUN_TIME = 275 # in seconds
  ENQUEUE_INTERVAL = 30 # The job will start 15 seconds after the TTL for the lock on the first job which is 5 minutes
  REMOVE_SAML_PROVIDER_TYPE = "Business::SamlProvider"

  # Public: Is this business configured to use SAML Single Sign-on or Open ID Connect for
  # its members?
  #
  # Returns a Boolean
  # If the provider is disabled and the customer is testing saml/oidc settings without saving
  def external_provider_enabled?
    saml_sso_enabled? || oidc_enabled?
  end

  # Public: External Identity provider configured for this business
  #
  # Returns a Boolean
  def external_provider
    saml_provider || oidc_provider
  end

  def async_external_provider
    if oidc_enabled?
      async_oidc_provider
    else
      async_saml_provider
    end
  end

  def oidc_enabled?
    return false if GitHub.single_business_environment?
    async_oidc_provider.then do |provider|
      provider.present? && provider.persisted?
    end.sync
  end

  # Public: Does the given user meet the SAML or OIDC requirements for the enterprise?
  #
  # user - User to check
  #
  # Returns Boolean
  def meets_sso_requirements?(user)
    if oidc_enabled?
      external_sso_requirement_met_by?(user)
    else
      saml_sso_requirement_met_by?(user)
    end
  end

  # Public: Is the given user already linked to the business via the
  # current external identity provider?
  #
  # Returns a Boolean
  def external_sso_requirement_met_by?(user)
    return true unless external_provider_enabled?
    # skip GHES with SCIM
    return true if enterprise_server_scim_enabled?
    user && ExternalIdentity.linked?(
      provider: external_provider,
      user: user
    )
  end

  # Public: Is the given user already linked to the business via the
  # current external identity provider?
  #
  # Returns a Boolean
  def external_sso_requirement_met_by_users?(user_ids)
    return true unless external_provider_enabled?
    # skip GHES with SCIM
    return true if enterprise_server_scim_enabled?
    user_ids&.any? && ExternalIdentity.by_provider(external_provider).where(user_id: user_ids).count == user_ids.count
  end

  # Public: Does this Enterprise Account enforce membership via a SAML identity provider?
  #
  # In GHEC, all Enterprises enforce SAML SSO if it's enabled.
  #
  # Returns a Boolean
  def external_sso_enforced?
    saml_sso_enforced? || oidc_enabled?
  end

  # Public: Find the object that contains the relevant external identity provider for the current
  # external identity session.
  #
  # Returns self
  def external_identity_session_owner
    self
  end

  # Public: Destroy all external provider dependents identities and groups, and reconcile teams.
  #
  # Returns nothing
  def destroy_external_provider_dependents(provider_id, provider_type)
    start_time = Time.now
    past_max_run_time = T.let(false, T::Boolean)

    external_group_ids = ExternalGroup.where(provider_id: provider_id, provider_type: provider_type).pluck(:id)

    past_max_run_time = delete_external_identity_group_members(start_time, external_group_ids) if external_group_ids.any?
    return start_new_job(provider_id, provider_type) if past_max_run_time

    past_max_run_time = reconcile_memberships(start_time, provider_id, provider_type, external_group_ids) if external_group_ids.any?
    return start_new_job(provider_id, provider_type) if past_max_run_time

    past_max_run_time = delete_external_group_teams(start_time, external_group_ids) if external_group_ids.any?
    return start_new_job(provider_id, provider_type) if past_max_run_time

    past_max_run_time = destroy_external_groups(start_time, external_group_ids) if external_group_ids.any?
    return start_new_job(provider_id, provider_type) if past_max_run_time

    past_max_run_time = destroy_external_identities(start_time, provider_id, provider_type)
    return start_new_job(provider_id, provider_type) if past_max_run_time

    del_removing_external_provider

    self.update_license_usage
  end

  # Description: Is the business currently removing an external provider?
  #
  # Returns a Boolean
  def removing_external_provider?
    !!GitHub.kv.get(external_provider_removal_key).value { nil }
  end

  # Description: The type of the external provider that is being removed.
  #
  # Returns a String
  def removing_external_provider_type
    GitHub.kv.get(external_provider_removal_key).value { nil }
  end

  # Description: Set the business as removing an external provider.
  #
  # Returns nothing
  def set_removing_external_provider(provider_type)
    GitHub.kv.set(external_provider_removal_key, provider_type, expires: 1.day.from_now)
  end

  private

  # Description: The key used to track if the business is removing an external provider.
  #
  # Returns a String
  def external_provider_removal_key
    "external-provider-removal:#{id}"
  end

  # Description: Remove the key used to track if the business is removing an external provider.
  #
  # Returns nothing
  def del_removing_external_provider
    GitHub.kv.del(external_provider_removal_key)
  end

  # Description: Is the job past the max run time?
  #
  # Returns a Boolean
  sig { params(start_time: Time).returns(T::Boolean) }
  def past_max_run_time?(start_time)
    Time.now.to_i - start_time.to_i >= MAX_RUN_TIME
  end

  # Description: Starts a new job of the given type with the provided arguments.
  # Parameters:
  # - provider_id - The ID of the provider that is being removed.
  # - provider_type - The type of the provider that is being removed: Business::SamlProvider or Business::OIDCProvider
  #
  # Returns nothing
  def start_new_job(provider_id, provider_type)
    options = {
      "info.message" => "Starting new job DestroyExternalProviderDependentsJob to destroy external provider dependents",
      "gh.job_args" => [provider_id, provider_type, id],
      "code.namespace" => self.class.name,
      "code.function" => "destroy_external_provider_dependents",
      "gh.external_provider.id" => provider_id,
      "gh.external_provider.type" => provider_type,
    }

    GitHub.logger.info(options)

    args = { provider_id: provider_id, provider_type: provider_type, business_id: id, caller: self.class.name }
    DestroyExternalProviderDependentsJob.enqueue_once_per_interval(kwargs: args, interval: ENQUEUE_INTERVAL, unique_id: id)
  end

  # Description: Removes external identity group members in batches of 10 groups at a time.
  # Parameters:
  # - start_time - The time the job started.
  # - external_group_ids - The IDs of the external groups to remove members from.
  #
  # Returns a Boolean
  def delete_external_identity_group_members(start_time, external_group_ids)
    past_max_run_time = T.let(false, T::Boolean)

    external_group_ids.each_slice(10) do |group_ids|
      ExternalIdentityGroupMembership.where(external_group_id: group_ids).delete_all

      break if past_max_run_time = past_max_run_time?(start_time)
    end

    past_max_run_time
  end

  # Description: Reconciles memberships for each external group team.
  # Parameters:
  # - start_time - The time the job started.
  # - provider_id - The ID of the provider that is being removed.
  # - provider_type - The type of the provider that is being removed: Business::SamlProvider or Business::OIDCProvider
  # - external_group_ids - The IDs of the external groups to reconcile memberships for.
  #
  # Returns a Boolean
  def reconcile_memberships(start_time, provider_id, provider_type, external_group_ids)
    past_max_run_time = T.let(false, T::Boolean)

    external_group_teams = ExternalGroupTeam.where(external_group_id: external_group_ids)
    return past_max_run_time?(start_time) unless external_group_teams.any?

    external_group_teams.each do |external_group_team|
      external_group_team.reconcile_memberships(
        job: DestroyExternalProviderDependentsJob,
        job_args: [],
        job_kwargs: { provider_id: provider_id, provider_type: provider_type, business_id: id, caller: self.class.name },
        start_time: start_time,
      )

      break if past_max_run_time = past_max_run_time?(start_time)
    end

    past_max_run_time
  end

  # Description: Removes external group teams in batches of 10 groups at a time.
  # Parameters:
  # - start_time - The time the job started.
  # - external_group_ids - The IDs of the external groups to remove teams from.
  #
  # Returns a Boolean
  def delete_external_group_teams(start_time, external_group_ids)
    past_max_run_time = T.let(false, T::Boolean)

    external_group_team_ids = ExternalGroupTeam.where(external_group_id: external_group_ids).pluck(:id)
    return past_max_run_time?(start_time) unless external_group_team_ids.any?

    external_group_team_ids.each_slice(10) do |group_team_ids|
      ExternalGroupTeam.where(id: group_team_ids).delete_all

      break if past_max_run_time = past_max_run_time?(start_time)
    end

    past_max_run_time
  end

  # Description: Removes external groups in batches of 10 groups at a time.
  # Parameters:
  # - start_time - The time the job started.
  # - external_group_ids - The IDs of the external groups to remove.
  #
  # Returns a Boolean
  def destroy_external_groups(start_time, external_group_ids)
    past_max_run_time = T.let(false, T::Boolean)

    external_group_ids.each_slice(10) do |group_ids|
      ExternalGroup.where(id: group_ids).destroy_all

      break if past_max_run_time = past_max_run_time?(start_time)
    end

    past_max_run_time
  end

  # Description: Removes external identities in batches of 10 groups at a time.
  # Parameters:
  # - start_time - The time the job started.
  # - provider_id - The ID of the provider that is being removed.
  # - provider_type - The type of the provider that is being removed: Business::SamlProvider or Business::OIDCProvider
  #
  # Returns a Boolean
  def destroy_external_identities(start_time, provider_id, provider_type)
    past_max_run_time = T.let(false, T::Boolean)

    external_identities = ExternalIdentity.where(provider_id: provider_id, provider_type: provider_type).pluck(:id)
    external_identities.each_slice(10) do |identity_ids|
      ExternalIdentity.where(id: identity_ids).destroy_all

      break if past_max_run_time = past_max_run_time?(start_time)
    end

    past_max_run_time
  end
end
