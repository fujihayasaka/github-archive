# typed: strict
# frozen_string_literal: true

# Background job that fans out one OauthEnterpriseLimitJob for each
# (app_id, user_id) pair for which the user holds an OAuth token, so the
# downstream writer can recompute GHEC higher-rate-limit eligibility and
# update the oauth_enterprise_limits table.
#
# Enqueued directly by the org.add_member and org.remove_member GlobalInstrumenter
# subscribers in config/instrumentation/oauth_enterprise_limits.rb, and fanned
# out per-user by OauthEnterpriseLimitUpdateOrganizationJob.
class OauthEnterpriseLimitUpdateUserJob < ApplicationJob
  queue_as :oauth_enterprise_limits
  retry_on_recoverable_exceptions
  discard_on ArgumentError
  retry_on_dirty_exit

  APPLICATION_BATCH_SIZE = 50

  sig { params(user_id: Integer).void }
  def perform(user_id:)
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

    user = User.find_by(id: user_id.to_i)
    return if user.nil?

    # find all distinct application IDs the user holds OAuth tokens for.
    app_ids_to_update = ::OauthAccess
      .where(application_type: "OauthApplication", user_id: user.id)
      .where.not(application_id: 0) # exclude classic PATs
      .distinct
      .pluck(:application_id)

    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.user_apps", app_ids_to_update.size)
    return if app_ids_to_update.empty?

    enqueued = 0

    app_ids_to_update.each_slice(APPLICATION_BATCH_SIZE) do |app_ids|
      jobs = app_ids.map { |app_id| OauthEnterpriseLimitJob.new(app_id:, user_id: user.id) }
      ActiveJob.perform_all_later(jobs) if jobs.any?
      enqueued += jobs.size
    end

    GitHub.logger.info("OauthEnterpriseLimitUpdateUserJob: fan-out complete", {
      "code.namespace": "OauthEnterpriseLimitUpdateUserJob",
      "code.function": "perform",
      "gh.user.id": user_id,
      "gh.user_apps_enqueued": enqueued,
    })
  end
end
