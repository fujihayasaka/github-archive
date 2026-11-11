# typed: strict
# frozen_string_literal: true

# Background job that fans out one OauthEnterpriseLimitUpdateOrganizationJob
# for each organization in a business, to recompute GHEC higher-rate-limit
# eligibility for org members' OAuth tokens after the business's effective
# plan changes (downgrade_at set or unset).
#
# Enqueued by Business's after_commit hook when `downgraded_at` changes
# (see Business::OauthEnterpriseLimitsDependency#recompute_oauth_enterprise_limits_for_orgs).
class OauthEnterpriseLimitUpdateBusinessJob < ApplicationJob
  queue_as :oauth_enterprise_limits
  retry_on_recoverable_exceptions
  discard_on ArgumentError
  retry_on_dirty_exit

  ORG_BATCH_SIZE = 500

  sig { params(business_id: Integer).void }
  def perform(business_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

    business = Business.find_by(id: business_id.to_i)
    return if business.nil?

    org_ids = business.organizations.pluck(:id)
    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.business_orgs", org_ids.size)
    return if org_ids.empty?

    enqueued = 0

    org_ids.each_slice(ORG_BATCH_SIZE) do |batch_org_ids|
      jobs = batch_org_ids.map { |oid| OauthEnterpriseLimitUpdateOrganizationJob.new(organization_id: oid) }
      ActiveJob.perform_all_later(jobs) if jobs.any?
      enqueued += jobs.size
    end

    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.business_orgs_enqueued", enqueued)
    GitHub.logger.info("OauthEnterpriseLimitUpdateBusinessJob: fan-out complete", {
      "code.namespace": "OauthEnterpriseLimitUpdateBusinessJob",
      "code.function": "perform",
      "gh.business.id": business_id,
      "gh.business_orgs": org_ids.size,
      "gh.business_orgs_enqueued": enqueued,
    })
  end
end
