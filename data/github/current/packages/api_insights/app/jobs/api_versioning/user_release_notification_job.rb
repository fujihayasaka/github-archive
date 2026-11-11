# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Sends API version release notification emails to users still on a prior
  # calendar version on the day the latest version is released.
  #
  # Sibling of `ApiVersioning::UserDeprecationNotificationJob` — they
  # process different cohorts (deprecating-version users vs. not-yet-on-
  # latest-version users) through different mailers (`DeprecationMailer`
  # vs. `ReleaseMailer`), and do not share an inheritance chain.
  #
  # See `BaseReleaseNotificationJob` for the full design rationale (mode
  # dispatch, dry-run, throttling, target-mode invariants,
  # per-invocation instance contract).
  class UserReleaseNotificationJob < BaseReleaseNotificationJob
    # Restated on each cohort subclass because ActiveJob::TenantContext
    # stores this marker in a class-instance variable on the declaring
    # class, and Ruby does NOT inherit class-instance variables. Without
    # this, the subclass appears non-exempt at runtime and the framework
    # skips the GitHub::CurrentTenant.unscope wrap around #perform.
    exempt_from_tenant_context_requirement

    # Persisted as part of the ActionRestraint dedup keys; renaming would
    # invalidate dedupe cells from any prior release-day run.
    ACTION_RESTRAINT_KEY = T.let("api_versioning_release_email", String)

    # Per-user dedupe window. Sized against the projected ~19h run
    # wall-clock for the user cohort (throttle-floor-dominated at
    # `EMAIL_ENQUEUE_RATE_LIMIT` = 500 enqueues/sec across
    # `ApiInsights::Stats::CalendarVersionUsage.users_count` rows). A 24h
    # cell would cut things uncomfortably close: a retry late in the run
    # could try to re-email the same user before the cell expires. 48h
    # gives ~2.5× headroom over the projected run and lines up with
    # `NotificationWave::RUNNING_TTL` on the deprecation pipeline, which
    # documents the same `total_wall (~19h) < TTL (48h) <
    # orchestrator_interval` invariant. The release path has no Redis
    # running keys — this ActionRestraint cell is the only per-user
    # dedupe between same-version retries / replays.
    PER_USER_DEDUPE_INTERVAL = T.let(48.hours, ActiveSupport::Duration)

    # Cohort tag emitted as the `cohort:` dogstats tag.
    COHORT = T.let("user", String)

    # Per-cohort kill-switch feature flag, evaluated by
    # `ReleaseNotificationDispatcherJob` (gating dispatch) and by the
    # per-batch stopping check in the base class. Release-pipeline
    # specific so the release and deprecation mail flows can be toggled
    # independently for the user cohort.
    COHORT_FEATURE_FLAG = T.let("api_versioning_release_emails_users_enabled", String)

    # deliver_later/sec budget consumed by the throttling logic in
    # `BaseReleaseNotificationJob#perform_batch`. User emails go to
    # exactly one recipient (no BCC fan-out), so 500 enqueues/sec hits
    # the ~500 outbound SMTP messages/sec cap directly.
    EMAIL_ENQUEUE_RATE_LIMIT = T.let(500, Integer)

    sig { override.returns(Integer) }
    def self.email_enqueue_rate_limit = EMAIL_ENQUEUE_RATE_LIMIT

    private

    sig { override.returns(String) }
    def cohort = COHORT

    sig { override.returns(String) }
    def cohort_feature_flag = COHORT_FEATURE_FLAG

    sig do
      override.params(
        latest_version: String,
        offset: Integer,
        batch_size: Integer,
      ).returns(T::Array[ApiInsights::Stats::CalendarVersionUsage::UserUsageRow])
    end
    def fetch_rows(latest_version, offset:, batch_size:)
      # `latest_version` is threaded through the base-class hook for
      # cohort-type symmetry but the user materialized view is not
      # version-scoped (it summarizes by actor_id, plus tenant_id in
      # Proxima), so we don't pass it on to the Stats layer. Per-version
      # dedup lives in the ActionRestraint key in `action_restraint_admit?`
      # below.
      ApiInsights::Stats::CalendarVersionUsage.users(offset: offset, batch_size: batch_size)
    end

    sig { override.params(latest_version: String).returns(Integer) }
    def fetch_count(latest_version)
      ApiInsights::Stats::CalendarVersionUsage.users_count
    end

    sig do
      override.params(
        latest_version: String,
        actor_id: Integer,
      ).returns(T::Array[ApiInsights::Stats::CalendarVersionUsage::UserUsageRow])
    end
    def fetch_for_actor(latest_version, actor_id:)
      ApiInsights::Stats::CalendarVersionUsage.user_for_actor(actor_id: actor_id)
    end

    sig { override.params(actor_ids: T::Array[Integer]).returns(T::Hash[Integer, User]) }
    def hydrate_actors(actor_ids)
      User.where(id: actor_ids).index_by(&:id)
    end

    sig { override.params(actor_id: Integer).returns(T.nilable(User)) }
    def find_actor(actor_id)
      User.find_by(id: actor_id)
    end

    sig { override.params(actor: User).returns(T::Boolean) }
    def actor_suspended?(actor)
      actor.suspended?
    end

    sig do
      override.params(
        row: ApiInsights::Stats::CalendarVersionUsage::UserUsageRow,
        latest_version: String,
      ).returns(T::Boolean)
    end
    def action_restraint_admit?(row, latest_version:)
      GitHub::ActionRestraint.perform?(
        ACTION_RESTRAINT_KEY,
        interval: PER_USER_DEDUPE_INTERVAL,
        version: latest_version,
        user_id: row.actor_id,
      )
    end

    sig do
      override.params(
        actor: User,
        row: ApiInsights::Stats::CalendarVersionUsage::UserUsageRow,
        latest_version: String,
        deprecating_versions: T::Hash[String, String],
      ).void
    end
    def deliver_mail(actor, row, latest_version:, deprecating_versions:)
      ApiVersioning::ReleaseMailer.for_user(
        actor,
        latest_version: latest_version,
        deprecating_versions: deprecating_versions,
      ).deliver_later
    end
  end
end
