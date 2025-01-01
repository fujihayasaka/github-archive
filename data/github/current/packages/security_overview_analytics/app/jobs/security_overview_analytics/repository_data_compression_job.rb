# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class RepositoryDataCompressionJob < BatchedJob
    include GitHub::Memoizer
    include BatchedJobThrottler
    include FanoutThrottler

    queue_as :security_overview_analytics_repository_data_cleanup

    locked_by timeout: 15.minutes, key: ->(job) do
      DEFAULT_LOCK_STRINGIFY_PROC.call([job.class.name])
    end

    FEATURES = %w[feature_status code_scanning secret_scanning dependabot].freeze

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # Job needs to be able to process repositories across multiple tenants.
    exempt_from_tenant_context_requirement

    use_replicas ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations

    sig do
      override.params(
        args: T.untyped,
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, offset_item_id:, **kwargs)
      SecurityOverviewAnalytics::Repository
        .where("repository_id > ?", offset_item_id)
        .order(:repository_id)
        .limit(BATCH_SIZE)
        .pluck(:repository_id)
    end

    sig do
      override.params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        offset_item_id: Integer,
        features: T.nilable(T::Array[String]),
        dry_run: T::Boolean,
        kwargs: T.untyped,
      ).void
    end
    def process_batch(repository_ids, *args, offset_item_id:, features: nil, dry_run: false, **kwargs)
      repository_owner_ids = T.let({}, T::Hash[Integer, Integer])
      repository_owner_ids.merge!(::Repository.active.where(id: repository_ids).pluck(:id, :owner_id).to_h)

      validation_result_by_owner_id = T.let({}, T::Hash[Integer, T::Boolean])
      repository_owner_ids.values.uniq.each do |owner_id|
        validation_result_by_owner_id.merge!(owner_id => should_perform_compression?(owner_id))
      end

      repo_ids_to_process = T.let([], T::Array[[Integer, Integer]])
      repository_ids.each do |repo_id|
        owner_id = T.must(repository_owner_ids[repo_id])
        validation_result = validation_result_by_owner_id[owner_id]
        repo_ids_to_process << [repo_id, owner_id] if validation_result
      end

      features = features.present? ? features & FEATURES : FEATURES

      GitHub.logger.info(
        "Repository data compression job processing repositories.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.features_to_process": features,
        "gh.security_overview_analytics.job.repository_ids": repository_ids,
        "gh.security_overview_analytics.job.repository_id_to_process": repo_ids_to_process,
      )

      repo_ids_to_process.each do |repository_id, owner_id|
        features.each do |feature|
          if feature == "feature_status"
            FeatureStatusDataCompressionJob.perform_later(repository_id:, owner_id:, dry_run:)
          else
            AlertDataCompressionJob.perform_later(feature:, repository_id:, owner_id:, dry_run:)
          end
        end
      end
    end

    sig { params(args: T::Array[T.untyped], options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    sig do
      override.params(
        ids: T::Array[Integer],
        args: T.untyped,
        kwargs: T.untyped,
      )
      .returns(T.nilable(Integer))
    end
    def next_batch_offset_item_id(ids, *args, **kwargs)
      ids.last
    end

    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [AlertDataCompressionJob, FeatureStatusDataCompressionJob]
    end

    private

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def should_perform_compression?(owner_id)
      owner = ::User.find_by!(id: owner_id)

      unless TenantValidationHelper.is_owner_in_scope?(owner)
        GitHub.logger.info(
          "Tenant data compression skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Tenant not in scope.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.tenant_compression.skipped",
          tags: all_stats_tags + ["reason:tenant_not_in_scope"]
        )
        return false
      end

      unless Initialization.for(owner).any_initialized?
        GitHub.logger.info(
          "Tenant data compression skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Tenant not initialized."
        )

        GitHub.dogstats.increment(
          "security_overview_analytics.tenant_compression.skipped",
          tags: all_stats_tags + ["reason:tenant_not_initialized"]
        )
        return false
      end

      true
    end
  end
end
