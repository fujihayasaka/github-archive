# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class AlertDataCompressionJob < BatchedJob
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
      feature = job.arguments.dig(0, :feature)
      DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id, feature])
    end

    resolve_tenant_context do |job_args|
      Repositories::Public.resolve_tenant(id: job_args[:repository_id])
    end

    IAlertRevision = T.type_alias do
      T.any(
        DependabotAlertRevision,
        CodeScanningAlertRevision,
        SecretScanningAlertRevision,
      )
    end

    TAlertRevision = T.type_alias do
      T.any(
        T.class_of(DependabotAlertRevision),
        T.class_of(CodeScanningAlertRevision),
        T.class_of(SecretScanningAlertRevision),
        T.class_of(FeatureStatusRevision),
      )
    end

    sig { override.params(args: T.untyped, kwargs: T.untyped).void }
    def perform(*args, **kwargs)
      log_timing(step: "perform") do
        GitHub::Restraint.new.lock!(T.must(self.class.name), restraint_lock_num_concurrent_jobs, restraint_lock_ttl_sec) do
          super(*T.unsafe(args), **kwargs)
        end
      end
    end

    sig do
      override.params(
        args: T.untyped,
        feature: String,
        repository_id: Integer,
        owner_id: Integer,
        offset_item_id: T.any(Integer, T.nilable(String)),
        kwargs: T.untyped
      ).returns(T::Array[Integer])
    end
    def next_batch(*args, feature:, repository_id:, owner_id:, offset_item_id:, **kwargs)
      log_timing(step: "next_batch") do
        return [] if offset_item_id.nil?

        model = T.must(feature_model(feature))
        model
          .where(repository_id:)
          .where("alert_number > ?", offset_item_id)
          .order(:alert_number)
          .limit(BATCH_SIZE)
          .pluck(:alert_number)
      end
    end

    sig do
      override.params(
        alert_numbers: T::Array[Integer],
        args: T.untyped,
        repository_id: Integer,
        feature: String,
        dry_run: T::Boolean,
        kwargs: T.untyped
      ).void
    end
    def process_batch(alert_numbers, *args, repository_id:, feature:, dry_run: false, **kwargs)
      model = T.must(feature_model(feature))
      revisions_count_by_alert_number = model.where(repository_id:, alert_number: alert_numbers.uniq).group(:alert_number).count
      # We decided on this assumption that if a repository has more than 3 revisions for a single alert number,
      # there is a higher chance for duplicate revisions.
      alert_revisions_to_compress = revisions_count_by_alert_number.select { |_, v| v > 3 }.keys

      log_timing(step: "process_batch") do
        alert_revisions_to_compress.each do |alert_number|
          model.compress_revisions(alert_number:, repository_id:, dry_run:)
        end
      end

      GitHub.logger.info(
        "Alert data compression job compressing revisions.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.alert_numbers": alert_revisions_to_compress,
      )
    end

    sig { override.params(args: T.untyped, options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    sig { override.params(batch: T::Array[Integer], args: T.untyped, options: T.untyped).returns(T.nilable(Integer)) }
    def next_batch_offset_item_id(batch, *args, **options)
      batch.max
    end

    private

    sig { params(feature: String).returns(T.nilable(TAlertRevision)) }
    def feature_model(feature)
      case feature
      when "code_scanning"
        CodeScanningAlertRevision
      when "secret_scanning"
        SecretScanningAlertRevision
      when "dependabot"
        DependabotAlertRevision
      when "feature_status"
        FeatureStatusRevision
      else
        nil
      end
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments[0] || {}
      repository_id = arguments.dig(0, :repository_id)
      owner_id = arguments.dig(0, :owner_id)
      feature = arguments.dig(0, :feature)
      initial_start = kwargs.fetch(:initial_start, Time.current.utc)

      super.merge({
        "gh.batched_job.initial_start": initial_start,
        "gh.batched_job.offset_item_id": kwargs[:offset_item_id],
        "gh.batched_job.restraint_lock_num_concurrent_jobs": restraint_lock_num_concurrent_jobs,
        "gh.batched_job.restraint_lock_ttl_sec": restraint_lock_ttl_sec,
        "gh.job.restraint_lock.retry.count": exception_executions[[GitHub::Restraint::UnableToLock].to_s] || 0,
        "gh.owner.id": owner_id,
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.data_compression.feature": feature,
      })
    end

    sig { returns(Integer) }
    def restraint_lock_num_concurrent_jobs
      return DEFAULT_NUMBER_OF_CONCURRENT_JOBS unless FeatureFlag.vexi.percentage_of_actors_value_or_raise(:soa_data_compression_job_restraint_lock_num_concurrent_jobs) > 0 # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      # percentage_of_actors_value ranges from 0.01 to 100
      FeatureFlag # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
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
