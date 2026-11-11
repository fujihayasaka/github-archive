# typed: strict
# frozen_string_literal: true

# Background job that fans out one OauthEnterpriseLimitUpdateUserJob for each
# org member who has at least one OAuth token, to recompute the GHEC
# higher-rate-limit eligibility and update the oauth_enterprise_limits table.
#
# Enqueued by the GlobalInstrumenter subscribers in
# config/instrumentation/oauth_enterprise_limits.rb for billing.plan_change
# and the enterprise_account.organization_{add,remove,transfer,upgrade}
# events, and fanned out per-organization by OauthEnterpriseLimitUpdateBusinessJob.
class OauthEnterpriseLimitUpdateOrganizationJob < ApplicationJob
  queue_as :oauth_enterprise_limits
  retry_on_recoverable_exceptions
  discard_on ArgumentError
  retry_on_dirty_exit

  USER_BATCH_SIZE = 1000

  sig { params(organization_id: Integer).void }
  def perform(organization_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

    org = T.cast(Orgs.domain.by_id(organization_id.to_i), T.nilable(Organization))
    return if org.nil?

    # Get org member IDs via the abilities system. This includes both direct
    # and indirect members (e.g., via business teams), which is intentional since
    # indirect members also benefit from GHEC higher rate limits.
    # Bounded by org/business membership count rather than token count,
    # avoiding scanning millions of oauth_accesses rows for popular apps.
    member_user_ids = org.member_ids
    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.org_members", member_user_ids.size)
    return if member_user_ids.empty?

    enqueued = 0

    member_user_ids.each_slice(USER_BATCH_SIZE) do |batch_user_ids|
      # Filter to avoid enqueuing user jobs for members with no OAuth tokens
      user_ids_with_tokens = OauthAccess
        .where(application_type: "OauthApplication", user_id: batch_user_ids)
        .where.not(application_id: 0) # exclude classic PATs
        .distinct
        .pluck(:user_id)

      jobs = user_ids_with_tokens.map { |uid| OauthEnterpriseLimitUpdateUserJob.new(user_id: uid) }
      ActiveJob.perform_all_later(jobs) if jobs.any?
      enqueued += jobs.size
    end

    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.org_members_enqueued", enqueued)
    GitHub.logger.info("OauthEnterpriseLimitUpdateOrganizationJob: fan-out complete", {
      "code.namespace": "OauthEnterpriseLimitUpdateOrganizationJob",
      "code.function": "perform",
      "gh.org.id": organization_id,
      "gh.org_members": member_user_ids.size,
      "gh.org_members_enqueued": enqueued,
    })
  end
end
