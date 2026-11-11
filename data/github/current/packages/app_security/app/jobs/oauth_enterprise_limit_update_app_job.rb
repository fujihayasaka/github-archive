# typed: strict
# frozen_string_literal: true

# Background job that fans out one OauthEnterpriseLimitJob for each
# (app_id, user_id) pair where a user holds an OAuth token for the given app,
# so the downstream writer can recompute GHEC higher-rate-limit eligibility
# and update the oauth_enterprise_limits table.
#
# Enqueued directly by the oauth_application.transfer GlobalInstrumenter
# subscriber in config/instrumentation/oauth_enterprise_limits.rb. App
# transfer changes the app's owner (affecting Api::RequestOwner matching) and
# destroys approvals for the target organization, so every existing token for
# the app may have its eligibility flip.
class OauthEnterpriseLimitUpdateAppJob < BatchedJob
  queue_as :oauth_enterprise_limits
  retry_on_recoverable_exceptions
  discard_on ArgumentError
  retry_on_dirty_exit

  BATCH_SIZE = 1000


  sig { params(application_id: Integer, offset_item_id: Integer, options: T.untyped).returns(T::Array[OauthAccess]) }
  def next_batch(application_id, offset_item_id: 0, **options)
    return [] unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_app_transfer_events, default: false)

    return [] if application_id.to_i == 0 # classic PATs are not real apps

    ::OauthAccess
      .where(application_type: "OauthApplication", application_id: application_id)
      .where("id > ?", offset_item_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig { params(items: T::Array[OauthAccess], application_id: Integer, options: T.untyped).void }
  def process_batch(items, application_id, **options)
    user_ids = items.pluck(:user_id).uniq

    jobs = user_ids.map { |uid| OauthEnterpriseLimitJob.new(app_id: application_id, user_id: uid) }
    ActiveJob.perform_all_later(jobs) if jobs.any?

    GitHub.dogstats.histogram("oauth_enterprise_limit.handle_change.app_users", jobs.size)

    GitHub.logger.info("OauthEnterpriseLimitUpdateAppJob: fan-out complete", {
      "code.namespace": "OauthEnterpriseLimitUpdateAppJob",
      "code.function": "perform",
      "gh.oauth_application.id": application_id,
      "gh.app_users_enqueued": jobs.size,
    })
  end
end
