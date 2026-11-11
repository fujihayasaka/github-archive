# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Daily orchestrator that checks for API versions approaching deprecation
  # and fans out per-cohort notification jobs for each qualifying version.
  #
  # Each version/cohort/wave combination is gated on two Redis keys to prevent
  # both same-day overlap and unnecessary next-day re-querying:
  #
  #   - running_key  — set atomically at the start of a cohort run (NX); skipped if present
  #   - completed_key — set by the cohort job on its final page; skipped if present
  #
  # See DeprecationNotificationWave for key formats and TTLs.
  #
  # == Scheduling constraint
  #
  # This job's scheduled interval MUST be strictly greater than
  # NotificationWave::RUNNING_TTL (currently 48 h). If a run crashes, its
  # running-key lock persists for up to RUNNING_TTL; an orchestrator tick
  # that fires while the lock is still live will see the stale key and skip
  # the cohort. A 3-day cadence (interval: 3.days) satisfies this with
  # headroom. The current `interval: 1.day` is acceptable only while the
  # `condition: -> { false }` gate keeps the schedule disabled; revisit
  # when wiring up real production scheduling.
  #
  # == Review lab / manual testing
  #
  # Pass +dry_run_config+ to override production behaviour without touching feature flags:
  #
  #   # Force dry_run=true, use normal date-window filter:
  #   DeprecationCheckJob.perform_now(dry_run_config: {})
  #
  #   # Force dry_run=true AND bypass the date-window filter for a specific version:
  #   DeprecationCheckJob.perform_now(dry_run_config: { "force_version" => "2022-11-28" })
  #
  # Because +force_version+ lives *inside* +dry_run_config+, it is structurally
  # impossible to bypass the date window without also forcing a dry run.
  class DeprecationCheckJob < ApplicationJob
    queue_as :mailers

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # TODO: Restore to `condition: -> { !GitHub.enterprise? }` after testing is complete
    schedule interval: 1.day, condition: -> { false }
    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    sig { params(dry_run_config: T.nilable(T::Hash[String, String])).void }
    def perform(dry_run_config: nil)
      unless FeatureFlag.vexi.enabled?("api_versioning_deprecation_emails_enabled", default: false)
        GitHub.logger.info("DeprecationCheckJob: skipping — api_versioning_deprecation_emails_enabled is off")
        return
      end

      correlation_id = SecureRandom.uuid

      # When dry_run_config is provided it always forces dry_run=true, regardless of the flag.
      # This prevents accidental live sends during manual/review-lab invocations.
      dry_run = if dry_run_config
        true
      else
        FeatureFlag.vexi.enabled?("api_versioning_deprecation_emails_dry_run", default: true)
      end

      force_version = dry_run_config&.fetch("force_version", nil)

      GitHub.logger.info(
        "DeprecationCheckJob starting",
        "gh.dry_run_config" => dry_run_config.inspect,
        "gh.force_version" => force_version,
        "gh.dry_run" => dry_run,
        "gh.correlation_id" => correlation_id,
      )

      versions = if force_version
        GitHub.logger.info("DeprecationCheckJob: bypassing date-window filter", "gh.force_version" => force_version, "gh.correlation_id" => correlation_id)
        [force_version]
      else
        Api::Versioning.versions_deprecating_within(
          DeprecationNotificationWave::ALL.map(&:threshold_days).max,
        )
      end

      versions.each do |version|
        deprecation_date = Api::Versioning.deprecation_date_for(version)
        unless deprecation_date
          GitHub.logger.info("DeprecationCheckJob: skipping version — no deprecation date configured", "gh.version" => version, "gh.correlation_id" => correlation_id)
          next
        end

        latest_version = Api::Versioning.latest_version
        unless latest_version
          GitHub.logger.info("DeprecationCheckJob: skipping version — no latest_version configured", "gh.version" => version, "gh.correlation_id" => correlation_id)
          next
        end

        days_remaining = (deprecation_date - Date.today).to_i
        if days_remaining < 0
          GitHub.logger.info("DeprecationCheckJob: skipping version — deprecation date is in the past", "gh.version" => version, "gh.days_remaining" => days_remaining, "gh.correlation_id" => correlation_id)
          next
        end

        # When force_version is set the version may be outside all wave windows (> 180 days).
        # Default to BASIC so the dry run still exercises the full pipeline.
        wave = DeprecationNotificationWave.for_days_remaining(days_remaining) ||
          (force_version ? DeprecationNotificationWave::BASIC : nil)
        unless wave
          GitHub.logger.info("DeprecationCheckJob: skipping version — no matching wave", "gh.version" => version, "gh.days_remaining" => days_remaining, "gh.correlation_id" => correlation_id)
          next
        end

        GitHub.logger.info(
          "DeprecationCheckJob: processing version",
          "gh.version" => version,
          "gh.wave" => wave.identifier,
          "gh.days_remaining" => days_remaining,
          "gh.dry_run" => dry_run,
          "gh.correlation_id" => correlation_id,
        )

        cohorts_dispatched = 0

        BaseDeprecationNotificationJob.cohort_jobs.each do |job_class|
          cohort = job_class.cohort_identifier
          unless FeatureFlag.vexi.enabled?(job_class.cohort_feature_flag_name, default: false)
            GitHub.logger.info("DeprecationCheckJob: skipping cohort — feature flag disabled", "gh.cohort" => cohort, "gh.version" => version, "gh.wave" => wave.identifier, "gh.correlation_id" => correlation_id)
            next
          end

          if cohort_already_processed?(version, cohort, wave)
            GitHub.logger.info("DeprecationCheckJob: skipping cohort — already processed", "gh.cohort" => cohort, "gh.version" => version, "gh.wave" => wave.identifier, "gh.correlation_id" => correlation_id)
            next
          end

          job_class.perform_later(
            version,
            deprecation_date: deprecation_date.iso8601,
            latest_version: latest_version,
            wave_identifier: wave.identifier,
            correlation_id: correlation_id,
            dry_run: dry_run,
          )
          GitHub.logger.info("DeprecationCheckJob: dispatched cohort job", "gh.cohort" => cohort, "gh.version" => version, "gh.wave" => wave.identifier, "gh.dry_run" => dry_run, "gh.correlation_id" => correlation_id)
          cohorts_dispatched += 1
        end

        if cohorts_dispatched > 0
          GitHub.dogstats.increment(
            "api_versioning.deprecation_check.versions_dispatched",
            tags: ["version:#{version}", "wave:#{wave.identifier}"],
          )
        end
      end

      GitHub.dogstats.count(
        "api_versioning.deprecation_check.total_versions",
        versions.size,
      )

      GitHub.logger.info("DeprecationCheckJob complete", "gh.total_versions" => versions.size, "gh.correlation_id" => correlation_id)
    end

    private

    # Returns true if this cohort/version/wave has either a running or completed
    # Redis key, meaning the orchestrator should skip re-enqueueing it.
    sig { params(version: String, cohort: String, wave: NotificationWave).returns(T::Boolean) }
    def cohort_already_processed?(version, cohort, wave)
      redis = GitHub.legacy_redis
      redis.exists?(wave.completed_key(version: version, cohort: cohort)) ||
        redis.exists?(wave.running_key(version: version, cohort: cohort))
    end
  end
end
