# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class DataRetentionEnforcementJob < BatchedJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :security_overview_analytics_data_retention_enforcement

    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
    schedule interval: 1.week, scope: :global

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer

    # Job needs to be able to process repositories across multiple tenants.
    exempt_from_tenant_context_requirement

    use_replicas ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations

    # We limit to have one retention job session at all time.
    locked_by timeout: 15.minutes, key: ->(job) do
      job.class.name
    end

    around_perform do |job, block|
      job.arguments << {} if job.arguments.empty?
      min_next_date_id = job.arguments.dig(0, :min_next_date_id)

      if min_next_date_id.nil?
        job.arguments.first.merge!(min_next_date_id: Date.min_next_date_id)
      end

      block.call
    end

    sig do
      override.params(
        args: T.untyped,
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, offset_item_id:, **kwargs)
      ::SecurityOverviewAnalytics::Repository
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
        kwargs: T.untyped,
      ).void
    end
    def process_batch(repository_ids, *args, offset_item_id:, **kwargs)
      revision_based_models = [
        FeatureStatusRevision,
        DependabotAlertRevision,
        CodeScanningAlertRevision,
        SecretScanningAlertRevision
      ]
      non_revision_based_models = [
        CodeScanningPullRequestAlert
      ]
      (revision_based_models + non_revision_based_models).map do |model|
        GitHub.dogstats.distribution_time(
          "security_overview_analytics.data_retention_enforcement.dist",
          tags: all_stats_tags + ["table:#{model.table_name}"]
        ) do
          model.where(repository_id: repository_ids).then do |rel|
            if revision_based_models.include?(model)
              # By filtering with "next_revision_date_id < min_next_date_id",
              # we will get all revisions beyond retention limit except for one
              # which should be the most recent revision beyond retention limit.
              # This is necessary to build a proper trend across entire retention duration.
              rel.where("next_revision_date_id < ?", min_next_date_id)
            elsif non_revision_based_models.include?(model)
              rel.where("date_id < ?", min_next_date_id)
            else
              rel.none
            end
          end.in_batches(of: BATCH_SIZE) do |batch|
            rows = batch.pluck(:repository_id, :alert_number, :date_id)
            instrument_rows_for_removal(table_name: model.table_name, rows:)

            model.throttle_writes_with_retry do
              batch.delete_all
            end
          end
        end
      end
    end

    sig do
      override.params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        kwargs: T.untyped
      ).returns(T.nilable(Integer))
    end
    def next_batch_offset_item_id(repository_ids, *args, **kwargs)
      # Ids are sorted in ascending order thus last id is the largest
      repository_ids.last
    end

    sig do
      params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        kwargs: T.untyped
      ).void
    end
    def finalize_batch(repository_ids, *args, **kwargs)
      # Because we are manually taking an exclusive hash lock on the entire session, subsequent batches will be blocked
      # until we release the lock here.
      clear_lock
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_overview_analytics.job.min_next_date_id": arguments.dig(0, :min_next_date_id),
        "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress)
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    private

    sig { returns(Integer) }
    memoize def min_next_date_id
      arguments.dig(0, :min_next_date_id)
    end

    sig { params(table_name: String, rows: T::Array[T.untyped]).void }
    def instrument_rows_for_removal(table_name:, rows:)
      GitHub.logger.info(
        "Revisions expected to be removed.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.table": table_name,
        "gh.security_overview_analytics.job.revisions": rows.inspect,
      )
      GitHub.dogstats.count(
        "security_overview_analytics.data_retention_enforcement.revisions_to_remove",
        rows.size,
        tags: all_stats_tags + ["table:#{table_name}"]
      )
    end
  end
end
