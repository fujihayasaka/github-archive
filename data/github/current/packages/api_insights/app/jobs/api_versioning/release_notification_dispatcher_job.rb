# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Daily orchestrator that, on the day the latest API calendar version is
  # released, fans out the per-user release notification job. Skips silently
  # on every other day; the heavy Kusto work happens only inside the
  # per-cohort job that this class dispatches.
  #
  # Release-day detection is delegated to `Api::Versioning` so this job
  # stays behaviour-only — see `latest_version_released_today?` and
  # `deprecating_versions_with_dates` for the configuration contract.
  #
  # == Review lab / manual testing
  #
  # Pass +dry_run_config+ to override production behaviour without touching
  # feature flags:
  #
  #   # Force dry_run=true, use real release-day detection:
  #   ReleaseNotificationDispatcherJob.perform_now(dry_run_config: {})
  #
  #   # Force dry_run=true AND bypass release-day detection for a specific version:
  #   ReleaseNotificationDispatcherJob.perform_now(dry_run_config: { "force_version" => "2026-03-10" })
  #
  # Because +force_version+ lives *inside* +dry_run_config+, it is
  # structurally impossible to bypass the release-day check without also
  # forcing a dry run.
  class ReleaseNotificationDispatcherJob < ApplicationJob
    # Dispatcher-level dedupe key. Persisted in Redis through
    # GitHub::ActionRestraint; renaming it would re-trigger a fan-out for
    # any release-day the dispatcher has already processed in the last
    # 48h. The cell is shared by dry-run and live invocations so that
    # only one `UserReleaseNotificationJob` chain — of either mode —
    # can be in flight per version at a time.
    DISPATCH_ACTION_RESTRAINT_KEY = T.let("api_versioning_release_dispatch", String)

    # How long the dispatcher dedupe cell lives. Sized against the
    # projected ~19h wall-clock of the downstream
    # `UserReleaseNotificationJob` chain (throttle-floor-dominated at
    # 500 enqueues/sec across the user cohort). The cell must outlast
    # the chain so that an in-flight retry that re-enters this
    # dispatcher cannot fan out a second `UserReleaseNotificationJob`
    # while the first is still draining. 48h gives ~2.5× headroom and
    # matches `UserReleaseNotificationJob::PER_USER_DEDUPE_INTERVAL` and
    # `NotificationWave::RUNNING_TTL` on the deprecation pipeline; the
    # shared invariant is `total_wall (~19h) < TTL (48h) <
    # orchestrator_interval`. The current schedule uses
    # `interval: 1.day` only because `condition: -> { false }` keeps the
    # scheduler off; revisit (probably 3.days) when wiring up real
    # production scheduling so the invariant still holds.
    DISPATCH_DEDUPE_INTERVAL = T.let(48.hours, ActiveSupport::Duration)

    queue_as :mailers

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # TODO: Restore to `condition: -> { !GitHub.enterprise? }` after testing is complete
    schedule interval: 1.day, condition: -> { false }
    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    sig { params(dry_run_config: T.nilable(T::Hash[String, String])).void }
    def perform(dry_run_config: nil)
      unless FeatureFlag.vexi.enabled?("api_versioning_release_emails_enabled", default: false)
        GitHub.logger.info("ReleaseNotificationDispatcherJob: skipping — api_versioning_release_emails_enabled is off")
        return
      end

      correlation_id = SecureRandom.uuid

      # When dry_run_config is provided it always forces dry_run=true,
      # regardless of the flag. This prevents accidental live sends during
      # manual/review-lab invocations.
      dry_run = if dry_run_config
        true
      else
        FeatureFlag.vexi.enabled?("api_versioning_release_emails_dry_run", default: true)
      end

      force_version = dry_run_config&.fetch("force_version", nil)

      GitHub.logger.info(
        "ReleaseNotificationDispatcherJob starting",
        "gh.dry_run_config" => dry_run_config.inspect,
        "gh.force_version" => force_version,
        "gh.dry_run" => dry_run,
        "gh.correlation_id" => correlation_id,
      )

      latest_version = if force_version
        # force_version bypasses release-day detection. It is only reachable
        # via dry_run_config, so this branch is always dry-run.
        GitHub.logger.info(
          "ReleaseNotificationDispatcherJob: bypassing release-day check",
          "gh.force_version" => force_version,
          "gh.correlation_id" => correlation_id,
        )
        force_version
      else
        unless Api::Versioning.latest_version_released_today?
          GitHub.logger.info(
            "ReleaseNotificationDispatcherJob: skipping — latest version not released today",
            "gh.latest_version" => Api::Versioning.latest_version,
            "gh.correlation_id" => correlation_id,
          )
          return
        end
        Api::Versioning.latest_version
      end

      unless latest_version
        GitHub.logger.info(
          "ReleaseNotificationDispatcherJob: skipping — no latest_version configured",
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      # Dispatcher dedupe. The cell is shared by dry-run and live
      # invocations so only one `UserReleaseNotificationJob` chain
      # of either mode can be in flight per version at a time.
      unless GitHub::ActionRestraint.perform?(
        DISPATCH_ACTION_RESTRAINT_KEY,
        interval: DISPATCH_DEDUPE_INTERVAL,
        version: latest_version,
      )
        GitHub.logger.info(
          "ReleaseNotificationDispatcherJob: skipping — already dispatched within #{DISPATCH_DEDUPE_INTERVAL.inspect}",
          "gh.latest_version" => latest_version,
          "gh.dry_run" => dry_run,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      unless FeatureFlag.vexi.enabled?("api_versioning_release_emails_users_enabled", default: false)
        GitHub.logger.info(
          "ReleaseNotificationDispatcherJob: skipping users cohort — feature flag disabled",
          "gh.latest_version" => latest_version,
          "gh.correlation_id" => correlation_id,
        )
        return
      end

      # Surface every still-pending deprecation date in the dispatched
      # payload so the per-user job (and ultimately the mailer) can embed
      # them. Excluding `latest_version` keeps the freshly-released version
      # out of its own deprecation-list copy in case it appears in the
      # configured deprecation dates.
      deprecating_versions = Api::Versioning.deprecating_versions_with_dates(excluding: latest_version)
        .transform_values(&:iso8601)

      UserReleaseNotificationJob.perform_later(
        latest_version,
        deprecating_versions: deprecating_versions,
        correlation_id: correlation_id,
        dry_run: dry_run,
      )

      GitHub.dogstats.increment(
        "api_versioning.release_notification_dispatch",
        tags: ["version:#{latest_version}", "dry_run:#{dry_run}"],
      )
      GitHub.logger.info(
        "ReleaseNotificationDispatcherJob: dispatched users cohort",
        "gh.latest_version" => latest_version,
        "gh.deprecating_versions" => deprecating_versions.keys,
        "gh.dry_run" => dry_run,
        "gh.correlation_id" => correlation_id,
      )
    end
  end
end
