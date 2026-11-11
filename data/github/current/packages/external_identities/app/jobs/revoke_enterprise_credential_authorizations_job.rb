# typed: true
# frozen_string_literal: true

# Job to revoke all credential authorizations for an enterprise and optionally revoke
# EMU user credentials (PATs and SSH keys).
#
# This job:
# - Revokes all credential authorizations for all organizations within the enterprise
# - Revokes all credential authorizations at the enterprise level
# - If the enterprise is EMU and revoke_emu_credentials is true, revokes all PATs and SSH keys
#   owned by all members of the enterprise
# - Verifies the actor is an enterprise owner or GitHub staff
class RevokeEnterpriseCredentialAuthorizationsJob < ApplicationJob
  queue_as :revoke_enterprise_credential_authorizations

  BATCH_SIZE = 500
  LOCK_KEY = "revoke-enterprise-credentials:"
  LOCK_TIMEOUT = 10.minutes
  MAX_CONCURRENT_JOBS = 1

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes, attempts: 3 do |_job, error|
    Failbot.report(error)
  end

  # Perform the revocation job
  #
  # actor_id - The ID of the User initiating the revocation (must be enterprise owner or staff)
  # enterprise_id - The ID of the Business (enterprise) whose credential authorizations should be revoked
  # revoke_emu_credentials - Boolean, if true and enterprise is EMU, also revoke user credentials
  def perform(actor_id, enterprise_id, revoke_emu_credentials: false)
    return if GitHub.enterprise?

    actor = User.find(actor_id)
    enterprise = Business.find(enterprise_id)

    # Verify actor has permission
    unless can_revoke?(actor, enterprise)
      raise ArgumentError, "Actor must be an enterprise owner or GitHub staff"
    end

    # Lock to prevent concurrent revocation jobs for the same enterprise
    lock!(enterprise_id) do
      perform_revocation(actor, enterprise, revoke_emu_credentials)
    end
  end

  # Perform the actual revocation logic with locking in place
  def perform_revocation(actor, enterprise, revoke_emu_credentials)
    revoked_items = {
      organization_credential_authorizations: 0,
      enterprise_credential_authorizations: 0,
      organization_programmatic_access_grants: 0,
      classic_pats: 0,
      fine_grained_pats: 0,
      ssh_keys: 0
    }

    begin
      # Revoke all credential authorizations for all organizations in the enterprise
      revoke_organization_credential_authorizations(enterprise, actor, revoked_items)

      # Revoke all credential authorizations at the enterprise level
      revoke_enterprise_credential_authorizations(enterprise, actor, revoked_items)

      # Revoke all organization programmatic access grants for all organizations in the enterprise
      revoke_organization_programmatic_access_grants(enterprise, actor, revoked_items)

      # If EMU and flag is set, revoke user credentials (PATs and SSH keys)
      if revoke_emu_credentials && enterprise.enterprise_managed_user_enabled?
        revoke_emu_user_credentials(enterprise, actor, revoked_items)
      end
    ensure
      # Log revocation summary
      GitHub.logger.info(
        "RevokeEnterpriseCredentialAuthorizationsJob completed",
        enterprise_id: enterprise.id,
        enterprise_slug: enterprise.slug,
        actor_id: actor.id,
        actor_login: actor.display_login,
        organization_credential_authorizations_revoked: revoked_items[:organization_credential_authorizations],
        enterprise_credential_authorizations_revoked: revoked_items[:enterprise_credential_authorizations],
        organization_programmatic_access_grants_revoked: revoked_items[:organization_programmatic_access_grants],
        classic_pats_revoked: revoked_items[:classic_pats],
        fine_grained_pats_revoked: revoked_items[:fine_grained_pats],
        ssh_keys_revoked: revoked_items[:ssh_keys],
        revoke_emu_credentials: revoke_emu_credentials
      )
    end
  end

  # Private: The restraint for locking and preventing simultaneous revocation jobs
  # for the same enterprise.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous revocation jobs
  # for the same enterprise.
  #
  # enterprise_id - The ID of the enterprise to lock on
  #
  # Yields to the block while holding the lock
  # Raises GitHub::Restraint::UnableToLock if another job is already running
  def lock!(enterprise_id)
    lock_key = "#{LOCK_KEY}#{enterprise_id}"
    restraint.lock!(lock_key, MAX_CONCURRENT_JOBS, LOCK_TIMEOUT) do
      yield
    end
  end

  private

  # Check if actor can perform the revocation
  def can_revoke?(actor, enterprise)
    return true if actor.site_admin?
    enterprise&.actor_can_write_credentials?(actor)
  end

  # Revoke all credential authorizations for all organizations in the enterprise
  def revoke_organization_credential_authorizations(enterprise, actor, revoked_items)
    # Process organizations in batches to avoid loading all IDs into memory
    enterprise.organizations.in_batches(of: BATCH_SIZE) do |org_relation|
      org_ids = org_relation.pluck(:id)

      # Query all credential authorizations for this batch of orgs
      Organization::CredentialAuthorization
        .active
        .where(organization_id: org_ids)
        .in_batches(of: BATCH_SIZE) do |batch|
          batch.find_each do |auth|
            revoke_single_credential_authorization(auth, actor, revoked_items)
          end
        end
    end
  end

  # Revoke all credential authorizations at the enterprise level
  def revoke_enterprise_credential_authorizations(enterprise, actor, revoked_items)
    # Query all active credential authorizations for this enterprise
    Business::CredentialAuthorization
      .active
      .by_business(business: enterprise)
      .in_batches(of: BATCH_SIZE) do |batch|
        batch.find_each do |auth|
          revoke_single_credential_authorization(auth, actor, revoked_items)
        end
      end
  end

  # Revoke all organization programmatic access grants for all organizations in the enterprise.
  # Uses ProgrammaticAccessGrant::Service.bulk_revoke which enqueues BulkRevokeProgrammaticAccessGrantsJob
  # to handle audit logging and notifications for each revoked grant.
  def revoke_organization_programmatic_access_grants(enterprise, actor, revoked_items)
    enterprise_sso_enabled = enterprise.external_provider_enabled?
    enterprise.organizations.each do |org|
      # Only process orgs with SSO enabled (either at enterprise or org level)
      next unless enterprise_sso_enabled || org.saml_sso_enabled?

      OrganizationProgrammaticAccessGrant
        .where(organization_id: org.id)
        .in_batches(of: BATCH_SIZE) do |batch|
          ProgrammaticAccessGrant.bulk_revoke(
            batch.pluck(:id),
            actor,
            org,
            revoke_reason: "revoke all organization programmatic access grants for enterprise"
          )
          revoked_items[:organization_programmatic_access_grants] += batch.count
        end
    end
  end

  # Revoke a single credential authorization (handles both Organization and Business)
  def revoke_single_credential_authorization(auth, actor, revoked_items)
    success = T.let(false, T::Boolean)

    with_write do
      # revoke methods on the cred auth models are not used here because they don't allow GitHub staff
      if auth.update(revoked_by_id: actor.id, revoked_at: Time.current)
        auth.instrument :revoke, actor: actor, owner: auth.actor
        success = true
      end
    end

    # Only record if the revocation was successful
    return unless success

    if auth.is_a?(Organization::CredentialAuthorization)
      revoked_items[:organization_credential_authorizations] += 1
    else
      revoked_items[:enterprise_credential_authorizations] += 1
    end
  end

  # Revoke EMU user credentials (PATs and SSH keys)
  def revoke_emu_user_credentials(enterprise, actor, revoked_items)
    # Process users in batches to avoid loading all IDs into memory
    enterprise.user_accounts.where.not(user_id: nil).in_batches(of: BATCH_SIZE) do |user_account_relation|
      user_ids = user_account_relation.pluck(:user_id).compact
      next if user_ids.empty?

      # Revoke classic PATs for this batch of users
      revoke_classic_pats_in_bulk(user_ids, actor, revoked_items)

      # Revoke fine-grained PATs for this batch of users
      revoke_fine_grained_pats_in_bulk(user_ids, actor, revoked_items)

      # Revoke SSH keys for this batch of users
      revoke_ssh_keys_in_bulk(user_ids, actor, revoked_items)
    end
  end

  # Revoke all classic personal access tokens (PAT v1) for multiple users in bulk
  def revoke_classic_pats_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :site_admin : :enterprise_admin

    # Query all classic PATs for this batch of users
    tokens = OauthAccessTokens.domain.by_users_and_application(
      user_ids,
      OauthApplication::PERSONAL_TOKENS_APPLICATION_ID,
      OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
    )

    tokens.each do |token|
      result = T.let(nil, T.nilable(GH::Result[T::Boolean]))
      with_write do
        result = OauthAccessTokens.domain.destroy(token.id, explanation, entry_point: :revoke_enterprise_credential_authorizations_job)
      end

      # Only record if the destroy was successful
      revoked_items[:classic_pats] += 1 if result&.ok?
    end
  end

  # Revoke all fine-grained personal access tokens (PAT v2) for multiple users in bulk
  def revoke_fine_grained_pats_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :site_admin : :enterprise_admin

    # Query all fine-grained PATs for this batch of users
    UserProgrammaticAccess
      .where(user_id: user_ids)
      .find_each do |access|
        result = T.let(nil, T.nilable(ProgrammaticAccessTokens::IResult))
        with_write do
          result = ProgrammaticAccess.destroy(access, explanation)
        end

        # Only record if the destroy was successful
        revoked_items[:fine_grained_pats] += 1 if result&.success?
      end
  end

  # Revoke all SSH keys for multiple users in bulk
  def revoke_ssh_keys_in_bulk(user_ids, actor, revoked_items)
    explanation = actor.site_admin? ? :removed_by_staff : :enterprise_admin

    # Query all SSH keys for this batch of users
    PublicKey
      .where(user_id: user_ids)
      .find_each do |key|
        destroyed = T.let(nil, T.untyped)
        with_write do
          destroyed = key.destroy_with_explanation(explanation)
        end

        # Only record if the destroy was successful
        revoked_items[:ssh_keys] += 1 if destroyed
      end
  end
end
