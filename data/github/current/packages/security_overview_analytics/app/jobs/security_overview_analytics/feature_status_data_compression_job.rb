# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class FeatureStatusDataCompressionJob < ApplicationJob
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper

    queue_as :security_overview_analytics_repository_data_cleanup

    DEFAULT_NUMBER_OF_CONCURRENT_JOBS = T.let(10, Integer)
    DEFAULT_RESTRAINT_LOCK_TTL = T.let(60.minutes.to_i, Integer)

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on(GitHub::Restraint::UnableToLock, wait: 10.seconds, jitter: 0.15, attempts: :unlimited)

    locked_by timeout: 15.minutes, key: ->(job) do
      repository_id = job.arguments.dig(0, :repository_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
    end

    resolve_tenant_context do |job_args|
      Repositories::Public.resolve_tenant(id: job_args[:repository_id])
    end

    sig do
      params(
        repository_id: Integer,
        owner_id: Integer,
        dry_run: T::Boolean,
      ).void
    end
    def perform(repository_id:, owner_id:, dry_run: false)
      log_timing(step: "perform") do
        GitHub::Restraint.new.lock!(T.must(self.class.name), restraint_lock_num_concurrent_jobs, restraint_lock_ttl_sec) do
          FeatureStatusRevision.compress_revisions(repository_id:, dry_run:)

          GitHub.logger.info(
            "Feature status data compression job compressing revisions.",
            "code.namespace": self.class.name,
            "code.function": __method__,
          )
        end
      end
    end

    private

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments[0] || {}
      repository_id = arguments.dig(0, :repository_id)
      owner_id = arguments.dig(0, :owner_id)
      initial_start = kwargs.fetch(:initial_start, Time.current.utc)
      dry_run = kwargs.fetch(:dry_run, T::Boolean)

      super.merge({
        "gh.job.initial_start": initial_start,
        "gh.job.restraint_lock_num_concurrent_jobs": restraint_lock_num_concurrent_jobs,
        "gh.job.restraint_lock_ttl_sec": restraint_lock_ttl_sec,
        "gh.job.restraint_lock.retry.count": exception_executions[[GitHub::Restraint::UnableToLock].to_s] || 0,
        "gh.owner.id": owner_id,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.data_compression.feature": "feature_status",
        "gh.security_overview_analytics.data_compression.dry_run": dry_run,
      })
    end

    sig { returns(Integer) }
    def restraint_lock_num_concurrent_jobs
      return DEFAULT_NUMBER_OF_CONCURRENT_JOBS unless FeatureFlag.vexi.percentage_of_actors_value_or_raise(:soa_data_compression_job_restraint_lock_num_concurrent_jobs) > 0 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      # percentage_of_actors_value ranges from 0.01 to 100
      FeatureFlag  # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        .vexi
        .percentage_of_actors_value_or_raise(:soa_data_compression_job_restraint_lock_num_concurrent_jobs)
        .floor
    end

    sig { returns(Integer) }
    def restraint_lock_ttl_sec
      return DEFAULT_RESTRAINT_LOCK_TTL unless FeatureFlag.vexi.percentage_of_actors_value_or_raise(:soa_data_compression_job_restraint_lock_ttl_minutes) > 0 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      # percentage_of_actors_value ranges from 0.01 to 100
      FeatureFlag # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        .vexi
        .percentage_of_actors_value_or_raise(:soa_data_compression_job_restraint_lock_ttl_minutes)
        .floor
        .minutes
        .to_i
    end
  end
end
