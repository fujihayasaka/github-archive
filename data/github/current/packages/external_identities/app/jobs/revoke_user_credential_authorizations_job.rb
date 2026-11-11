# typed: true
# frozen_string_literal: true

# Job to revoke all credential authorizations for a single user within an enterprise
# and optionally revoke EMU user credentials (PATs and SSH keys).
#
# This job:
# - Revokes all credential authorizations for the user across all organizations within the enterprise
# - Revokes all credential authorizations for the user at the enterprise level
# - Revokes all organization programmatic access grants for the user within the enterprise
# - If the enterprise is EMU and revoke_emu_credentials is true, revokes all PATs and SSH keys
#   owned by the user
# - Verifies the actor is an enterprise owner or GitHub staff
class RevokeUserCredentialAuthorizationsJob < ApplicationJob
  include CredentialRevocationMethods
  include GitHub::Memoizer

  queue_as :revoke_enterprise_credential_authorizations

  BATCH_SIZE = 500
  LOCK_KEY = "revoke-user-credentials:"
  LOCK_TIMEOUT = 5.minutes
  MAX_CONCURRENT_JOBS = 1
  METRICS_PREFIX = "revoke_user_credential_authorizations"

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: 2.minutes, attempts: 3 do |_job, error|
    Failbot.report(error)
  end

  # Perform the revocation job
  #
  # actor_id - The ID of the User initiating the revocation (must be enterprise owner or staff)
  # user_id - The ID of the User whose credentials should be revoked
  # enterprise_id - The ID of the Business (enterprise) to scope the revocation to
  # revoke_emu_credentials - Boolean, if true and enterprise is EMU, also revoke user credentials
  def perform(actor_id, user_id, enterprise_id, revoke_emu_credentials: false)
    return if GitHub.enterprise?

    enterprise = Business.find(enterprise_id)
    actor = User.find(actor_id)
    user = User.find(user_id)

    return if !(FeatureFlag.vexi.enabled?(:credential_revocation_single_user, enterprise, default: false) ||
                FeatureFlag.vexi.enabled?(:credential_revocation_single_user, actor, default: false))

    return if actor == user && !FeatureFlag.vexi.enabled?(:credential_self_revocation_single_user, actor, default: false)

    unless can_revoke?(actor, user, enterprise)
      raise ArgumentError, "Actor must be an enterprise owner or GitHub staff"
    end


    lock!(user_id) do
      perform_revocation(actor, user, enterprise, revoke_emu_credentials)
    end
  end

  def perform_revocation(actor, user, enterprise, revoke_emu_credentials)
    job_start = GitHub::Dogstats.monotonic_time
    GitHub.dogstats.increment("#{METRICS_PREFIX}.started")

    revoked_items = {
      organization_credential_authorizations: 0,
      enterprise_credential_authorizations: 0,
      organization_programmatic_access_grants: 0,
      classic_pat_authorizations: 0,
      ssh_key_authorizations: 0,
      oauth_app_token_authorizations: 0,
      classic_pats: 0,
      fine_grained_pats: 0,
      ssh_keys: 0
    }

    credentials_deleted = revoke_emu_credentials && enterprise.enterprise_managed_user_enabled? && user.enterprise_managed_business == enterprise

    begin
      GitHub.dogstats.distribution_time(
        "#{METRICS_PREFIX}.phase.org_credential_auths",
        set_default_host_tag: true
      ) do
        revoke_user_organization_credential_authorizations(user, enterprise, actor, revoked_items, credentials_deleted)
      end

      GitHub.dogstats.distribution_time(
        "#{METRICS_PREFIX}.phase.enterprise_credential_auths",
        set_default_host_tag: true
      ) do
        revoke_user_enterprise_credential_authorizations(user, enterprise, actor, revoked_items, credentials_deleted)
      end

      GitHub.dogstats.distribution_time(
        "#{METRICS_PREFIX}.phase.org_programmatic_access_grants",
        set_default_host_tag: true
      ) do
        revoke_user_organization_programmatic_access_grants(user, enterprise, actor, revoked_items)
      end

      if credentials_deleted
        # Guard: only revoke global credentials when the target user is actually
        # managed by this enterprise, to prevent cross-enterprise revocation.
        GitHub.dogstats.distribution_time(
          "#{METRICS_PREFIX}.phase.emu_user_credentials",
          set_default_host_tag: true
        ) do
          revoke_classic_pats_in_bulk([user.id], actor, revoked_items)
          revoke_fine_grained_pats_in_bulk([user.id], actor, revoked_items)
          revoke_ssh_keys_in_bulk([user.id], actor, revoked_items)
        end
      end

      if actor == user
        notify_user_of_self_revocation(user, enterprise, credentials_deleted, revoked_items)
      else
        notify_user_of_revocation(user, enterprise, credentials_deleted, revoked_items)

        if notify_admin_of_revocation?(actor, user)
          notify_admin_of_revocation(actor, user, enterprise, credentials_deleted, revoked_items)
        end
      end
    ensure
      # Emit per-type revocation counters (always emit, including zeros, so per-job
      # means and counts are accurate on dashboards). Shape matches
      # RevokeEnterpriseCredentialAuthorizationsJob so the two paths are dashboardable
      # side by side.
      revoked_items.each do |type, count|
        GitHub.dogstats.count("#{METRICS_PREFIX}.revoked", count, tags: ["type:#{type}"])
      end
      GitHub.dogstats.distribution_timing_since("#{METRICS_PREFIX}.total_duration", job_start)
      GitHub.dogstats.increment("#{METRICS_PREFIX}.completed")

      GitHub.logger.info(
        "RevokeUserCredentialAuthorizationsJob completed",
        enterprise_id: enterprise.id,
        enterprise_slug: enterprise.slug,
        user_id: user.id,
        user_login: user.display_login,
        actor_id: actor.id,
        actor_login: actor.display_login,
        total_duration_ms: GitHub::Dogstats.duration(job_start),
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
  # for the same user.
  #
  # Returns GitHub::Restraint
  memoize def restraint
    GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous revocation jobs
  # for the same user.
  #
  # user_id - The ID of the user to lock on
  #
  # Yields to the block while holding the lock
  # Raises GitHub::Restraint::UnableToLock if another job is already running
  def lock!(user_id)
    lock_key = "#{LOCK_KEY}#{user_id}"
    restraint.lock!(lock_key, MAX_CONCURRENT_JOBS, LOCK_TIMEOUT) do
      yield
    end
  end

  private

  def notify_user_of_revocation(user, enterprise, credentials_deleted, revoked_items)
    revoked_counts = build_revoked_counts(revoked_items, credentials_deleted)

    RevokedCredentialMailer.credential_authorization_revoked_single_user(
      user,
      enterprise.slug,
      credentials_deleted: credentials_deleted,
      revoked_counts: revoked_counts
    ).deliver_later
  end

  def notify_user_of_self_revocation(user, enterprise, credentials_deleted, revoked_items)
    revoked_counts = build_revoked_counts(revoked_items, credentials_deleted)

    RevokedCredentialMailer.credential_authorization_revoked_single_user_self(
      user,
      enterprise.slug,
      credentials_deleted: credentials_deleted,
      revoked_counts: revoked_counts
    ).deliver_later
  end

  def notify_admin_of_revocation(actor, target_user, enterprise, credentials_deleted, revoked_items)
    revoked_counts = build_revoked_counts(revoked_items, credentials_deleted)

    RevokedCredentialMailer.credential_authorization_revoked_single_user_admin_confirmation(
      actor,
      target_user,
      enterprise.slug,
      credentials_deleted: credentials_deleted,
      revoked_counts: revoked_counts
    ).deliver_later
  end

  # Returns true unless the actor is GitHub staff (Stafftools-initiated) or
  # the actor is revoking their own credentials.
  def notify_admin_of_revocation?(actor, target_user)
    return false if actor.site_admin?
    return false if actor == target_user

    true
  end

  # Map raw counters tracked by the job into the per-credential-type counts
  # rendered in both the user and admin confirmation emails.
  def build_revoked_counts(revoked_items, credentials_deleted)
    if credentials_deleted
      {
        fine_grained_pats: revoked_items[:fine_grained_pats],
        classic_pats: revoked_items[:classic_pats],
        ssh_keys: revoked_items[:ssh_keys],
        oauth_app_tokens: revoked_items[:oauth_app_token_authorizations]
      }
    else
      {
        fine_grained_pats: revoked_items[:organization_programmatic_access_grants],
        classic_pats: revoked_items[:classic_pat_authorizations],
        ssh_keys: revoked_items[:ssh_key_authorizations],
        oauth_app_tokens: revoked_items[:oauth_app_token_authorizations]
      }
    end
  end

  def can_revoke?(actor, user, enterprise)
    return true if actor.site_admin?
    enterprise&.actor_can_write_credentials?(actor) || actor == user
  end

  def revoke_user_organization_credential_authorizations(user, enterprise, actor, revoked_items, credentials_deleted)
    orgs_processed = 0

    enterprise.organizations.in_batches(of: BATCH_SIZE) do |org_relation|
      org_ids = org_relation.pluck(:id)
      orgs_processed += org_ids.size

      Organization::CredentialAuthorization
        .active
        .by_actor(actor: user)
        .where(organization_id: org_ids)
        .find_each do |auth|
          revoke_single_credential_authorization(auth, actor, revoked_items)
          next unless auth.revoked?

          update_credential_authorization_type_count(auth, revoked_items, credentials_deleted)
        end
    end

    GitHub.logger.info(
      "RevokeUserCredentialAuthorizationsJob org_credential_auths progress",
      enterprise_id: enterprise.id,
      orgs_processed: orgs_processed,
      revoked_so_far: revoked_items[:organization_credential_authorizations]
    )
  end

  def revoke_user_enterprise_credential_authorizations(user, enterprise, actor, revoked_items, credentials_deleted)
    Business::CredentialAuthorization
      .active
      .by_business(business: enterprise)
      .by_actor(actor: user)
      .find_each do |auth|
        revoke_single_credential_authorization(auth, actor, revoked_items)
        next unless auth.revoked?

        update_credential_authorization_type_count(auth, revoked_items, credentials_deleted)
      end
  end

  def revoke_user_organization_programmatic_access_grants(user, enterprise, actor, revoked_items)
    enterprise_sso_enabled = enterprise.external_provider_enabled?
    enterprise.organizations.find_each do |org|
      # Only process orgs with SSO enabled (either at enterprise or org level)
      next unless enterprise_sso_enabled || org.saml_sso_enabled?

      grant_ids = OrganizationProgrammaticAccessGrant
        .joins(:user_programmatic_access)
        .where(organization_id: org.id, user_programmatic_accesses: { user_id: user.id })
        .pluck(:id)

      next if grant_ids.empty?

      ProgrammaticAccessGrant.bulk_revoke(
        grant_ids,
        actor,
        org,
        revoke_reason: "revoke organization programmatic access grants for user in enterprise"
      )
      revoked_items[:organization_programmatic_access_grants] += grant_ids.size
    end
  end

  def update_credential_authorization_type_count(auth, revoked_items, credentials_deleted)
    if auth.is_application?
      revoked_items[:oauth_app_token_authorizations] += 1
    end

    return if credentials_deleted

    if auth.credential_type == "OauthAccess"
      revoked_items[:classic_pat_authorizations] += 1
    elsif auth.credential_type == "PublicKey"
      revoked_items[:ssh_key_authorizations] += 1
    end
  end
end
