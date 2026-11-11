# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Sends API version deprecation notification emails to users.
  #
  # The user cohort is no longer filtered by API version — the underlying
  # materialized view summarizes by `actor_id` (plus `tenant_id` in
  # Proxima), so each wave dispatch reaches every user that has made an
  # API call. Per-version dedup lives in the ActionRestraint key below
  # (`ACTION_RESTRAINT_KEY` + `version:` kwarg).
  #
  # See BaseDeprecationNotificationJob for the full design rationale (lock
  # acquisition, completed_key semantics, target-mode invariants,
  # per-invocation instance contract).
  class UserDeprecationNotificationJob < BaseDeprecationNotificationJob
    # Restated on each cohort subclass because ActiveJob::TenantContext stores
    # this marker in a class-instance variable on the declaring class, and Ruby
    # does NOT inherit class-instance variables. Without this, the subclass
    # appears non-exempt at runtime and the framework skips the
    # GitHub::CurrentTenant.unscope wrap around #perform — User.find_by then
    # filters out cross-tenant cohort rows in Proxima. Track follow-up:
    # convert to class_attribute in lib/active_job/tenant_context.rb.
    exempt_from_tenant_context_requirement

    # Persisted as part of the ActionRestraint dedup keys; changing it would
    # re-trigger sends to every user that had been deduped under the old key.
    ACTION_RESTRAINT_KEY = T.let("api_ver_dep_user", String)

    # Persisted as part of Redis running_key / completed_key strings and
    # emitted as the `cohort:` dogstats tag — changing it would invalidate
    # live keys and dashboards.
    COHORT = T.let("user", String)

    # Per-cohort kill-switch feature flag, evaluated by DeprecationCheckJob
    # (gating dispatch) and by the per-batch stopping check in the base class.
    COHORT_FEATURE_FLAG = T.let("api_versioning_deprecation_emails_users_enabled", String)

    # deliver_later/sec budget consumed by the throttling logic in
    # BaseDeprecationNotificationJob#perform_batch. Each user email goes to
    # exactly one recipient (no BCC fan-out), so 500 enqueues/sec hits the
    # ~500 outbound SMTP messages/sec cap directly.
    EMAIL_ENQUEUE_RATE_LIMIT = T.let(500, Integer)

    sig { override.returns(String) }
    def self.cohort_identifier = COHORT

    sig { override.returns(String) }
    def self.cohort_feature_flag_name = COHORT_FEATURE_FLAG

    sig { override.returns(Integer) }
    def self.email_enqueue_rate_limit = EMAIL_ENQUEUE_RATE_LIMIT

    private

    sig { override.returns(String) }
    def cohort = COHORT

    sig { override.returns(String) }
    def cohort_feature_flag = COHORT_FEATURE_FLAG

    sig do
      override.params(
        version: String,
        offset: Integer,
        batch_size: Integer,
      ).returns(T::Array[ApiInsights::Stats::CalendarVersionUsage::UserUsageRow])
    end
    def fetch_rows(version, offset:, batch_size:)
      # `version` is threaded through the base-class hook for cohort-type
      # symmetry but the user materialized view is no longer version-scoped,
      # so we don't pass it on to the Stats layer.
      ApiInsights::Stats::CalendarVersionUsage.users(offset: offset, batch_size: batch_size)
    end

    sig { override.params(version: String).returns(Integer) }
    def fetch_count(version)
      ApiInsights::Stats::CalendarVersionUsage.users_count
    end

    sig do
      override.params(
        version: String,
        actor_id: Integer,
      ).returns(T::Array[ApiInsights::Stats::CalendarVersionUsage::UserUsageRow])
    end
    def fetch_for_actor(version, actor_id:)
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
        wave: NotificationWave,
        version: String,
        wave_identifier: String,
      ).returns(T::Boolean)
    end
    def action_restraint_admit?(row, wave:, version:, wave_identifier:)
      GitHub::ActionRestraint.perform?(
        ACTION_RESTRAINT_KEY,
        interval: wave.send_cadence,
        user_id: row.actor_id,
        version: version,
        wave_identifier: wave_identifier,
      )
    end

    sig do
      override.params(
        actor: User,
        row: ApiInsights::Stats::CalendarVersionUsage::UserUsageRow,
        version: String,
        deprecation_date: String,
        latest_version: String,
        subject_prefix: String,
      ).void
    end
    def deliver_mail(actor, row, version:, deprecation_date:, latest_version:, subject_prefix:)
      ApiVersioning::DeprecationMailer.for_user(
        actor,
        deprecation_version: version,
        deprecation_date: deprecation_date,
        latest_version: latest_version,
        subject_prefix: subject_prefix,
      ).deliver_later
    end
  end
end
