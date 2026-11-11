# typed: strict
# frozen_string_literal: true

# Computes the OAuth request owner for a given (app_id, user_id) pair and
# writes the result to the oauth_enterprise_limits table on the authnd cluster.
#
# This mirrors the OAuth-app branch of Api::RequestOwner.call but operates
# asynchronously — triggered by model lifecycle events (OauthAccess creation,
# OauthApplicationApproval changes, etc.).
class OauthEnterpriseLimitWriter
  ORG_BATCH_SIZE = 500
  APPROVAL_CHANGE_BATCH_SIZE = 1000

  # Compute request owner for an OAuth app + user pair, then write the result.
  #
  # @param app_id [Integer] OauthApplication ID
  # @param user_id [Integer] User ID (the token holder)
  # @return [void]
  sig { params(app_id: Integer, user_id: Integer).void }
  def self.write_for(app_id:, user_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    app = OauthApplication.find_by(id: app_id)
    user = T.cast(Users.domain.by_id(user_id), T.nilable(User))

    if app.nil? || user.nil?
      OauthEnterpriseLimit.with_write do
        OauthEnterpriseLimit.remove_limit(app_id:, user_id:)
      end
      return
    end

    request_owner, higher_limit = compute_request_owner(app:, user:)

    if request_owner.nil? || !higher_limit
      OauthEnterpriseLimit.with_write do
        OauthEnterpriseLimit.remove_limit(app_id:, user_id:)
      end
      return
    end

    OauthEnterpriseLimit.with_write do
      OauthEnterpriseLimit.upsert_limit(
        app_id:,
        user_id:,
        request_owner_id: request_owner.id,
      )
    end
  end

  # Remove the limit row for the given app/user pair.
  #
  # @param app_id [Integer]
  # @param user_id [Integer]
  # @return [void]
  sig { params(app_id: Integer, user_id: Integer).void }
  def self.remove_for(app_id:, user_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    OauthEnterpriseLimit.with_write do
      OauthEnterpriseLimit.remove_limit(app_id:, user_id:)
    end
  end

  # Enqueue a background job to recompute limits for all users with active
  # OAuth tokens for a given app + org combination.
  #
  # @param app_id [Integer]
  # @param organization_id [Integer]
  # @return [void]
  sig { params(app_id: Integer, organization_id: Integer).void }
  def self.enqueue_for_approval_change(app_id:, organization_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    OauthEnterpriseLimitJob.perform_later(
      app_id:,
      organization_id:,
      action: "approval_change",
    )
  end

  # Recompute limits for ALL users who have active OAuth tokens for a given
  # app + org combination. Used when an OauthApplicationApproval changes.
  #
  # @param app_id [Integer]
  # @param organization_id [Integer]
  # @return [void]
  sig { params(app_id: Integer, organization_id: Integer).void }
  def self.write_for_approval_change(app_id:, organization_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits, default: false)

    org = T.cast(Orgs.domain.by_id(organization_id.to_i), T.nilable(Organization))
    return if org.nil?

    enqueued = 0

    # Get org member IDs via the abilities system. This includes both direct
    # and indirect members (e.g., via business teams), which is intentional since
    # indirect members also benefit from GHEC higher rate limits.
    # Bounded by org/business membership count rather than token count,
    # avoiding scanning millions of oauth_accesses rows for popular apps.
    member_user_ids = org.member_ids
    return if member_user_ids.empty?

    member_user_ids.each_slice(APPROVAL_CHANGE_BATCH_SIZE) do |batch_user_ids|
      # Find which members actually have an OAuth token for this app.
      # Uses index_oauth_accesses_on_user_id_and_appl_id_and_fingerprint.
      user_ids_with_tokens = OauthAccess
        .where(application_id: app_id, application_type: "OauthApplication", user_id: batch_user_ids)
        .distinct
        .pluck(:user_id)

      jobs = user_ids_with_tokens.map { |uid| OauthEnterpriseLimitJob.new(app_id:, user_id: uid) }
      ActiveJob.perform_all_later(jobs) if jobs.any?
      enqueued += jobs.size
    end

    GitHub.logger.info("OauthEnterpriseLimitWriter: approval_change fan-out complete", {
      "code.namespace": "OauthEnterpriseLimitWriter",
      "code.function": "write_for_approval_change",
      "gh.oauth_app.id": app_id,
      "gh.org.id": organization_id,
      "gh.users_enqueued": enqueued,
    })
  rescue => e
    GitHub.logger.warn("OauthEnterpriseLimitWriter: approval_change fan-out failed", {
      "code.namespace": "OauthEnterpriseLimitWriter",
      "code.function": "write_for_approval_change",
      "gh.oauth_app.id": app_id,
      "gh.org.id": organization_id,
    })
    Failbot.report(e, context: "OauthEnterpriseLimitWriter.write_for_approval_change",
                      app_id:, organization_id:)
  end

  # Compute request owner following the OAuth branch of Api::RequestOwner.call.
  #
  # Priority:
  # 1. App owner is in user's orgs → app owner
  # 2. OauthApplicationApproval for user's org → prefer GHEC-qualified org
  # 3. No match → nil
  #
  # @return [Array(User|Organization|nil, Boolean)] [request_owner, higher_limit_eligible]
  sig { params(app: OauthApplication, user: User).returns([T.nilable(T.any(User, Organization)), T::Boolean]) }
  def self.compute_request_owner(app:, user:)
    app_owner = app.user
    return [nil, false] if app_owner.nil?

    # Priority 1: app owner is one of user's orgs
    org_ids = user.organization_ids
    if org_ids.include?(app_owner.id)
      higher_limit = Api::RateLimitConfiguration.qualifies_for_higher_limit?(app_owner)
      return [app_owner, higher_limit]
    end

    # Priority 2: check OauthApplicationApproval for user's orgs (batched to
    # avoid unbounded IN clauses for users with many org memberships).
    # NOTE: We intentionally filter to approved state only, unlike Api::RequestOwner
    # (app/api/request_owner.rb:30) which includes all states. That is a bug — see #426076.
    org_ids.each_slice(ORG_BATCH_SIZE) do |batch|
      OauthApplicationApproval
        .approved
        .includes(:organization)
        .where(organization_id: batch, application_id: app.id)
        .each do |approval|
          if Api::RateLimitConfiguration.qualifies_for_higher_limit?(approval.organization)
            return [approval.organization, true]
          end
        end
    end

    # Priority 3: no match
    [nil, false]
  end
end
