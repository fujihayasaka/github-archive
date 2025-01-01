# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class RepositoryDataCompressionJob < BatchedJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :security_overview_analytics_repository_data_cleanup

    locked_by timeout: 15.minutes, key: ->(job) do
      DEFAULT_LOCK_STRINGIFY_PROC.call([job.class.name])
    end
    # TODO - add scheduling once the job has been tested and validated
    # locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
    # schedule interval: 1.day, scope: :global

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # Job needs to be able to process repositories across multiple tenants.
    exempt_from_tenant_context_requirement

    use_replicas ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations

    around_perform do |job, block|
      job.arguments << {} if job.arguments.empty?
      session_id = job.arguments.dig(0, :session_id)
      kv_session_id = Session.current

      if kv_session_id.nil?
        session_id = Session.lock!
        job.arguments.first.merge!(session_id: session_id)
        next block.call
      elsif kv_session_id == session_id
        next block.call
      end

      GitHub.dogstats.increment("security_center.repository_data_cleanup.session_exists", tags: job.all_stats_tags)
    end

    sig do
      override.params(
        args: T.untyped,
        owner_ids: T.nilable(T::Array[Integer]),
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, owner_ids:, offset_item_id:, **kwargs)
      # TODO - remove the owner_ids param once the job can fully run on schedule
      base_rel = if owner_ids.present?
        SecurityOverviewAnalytics::Repository.where(owner_id: owner_ids)
      else
        SecurityOverviewAnalytics::Repository
      end

      base_rel
        .where("repository_id > ?", offset_item_id)
        .order(:repository_id)
        .limit(BATCH_SIZE)
        .pluck(:repository_id)
    end

    sig do
      override.params(
        repository_ids: T::Array[Integer],
        args: T.untyped,
        features: T::Array[String],
        offset_item_id: Integer,
        dry_run: T::Boolean,
        kwargs: T.untyped,
      ).void
    end
    def process_batch(repository_ids, *args, features:, offset_item_id:, dry_run: false, **kwargs)
      repository_owner_ids = T.let({}, T::Hash[Integer, Integer])
      repository_owner_ids.merge!(::Repository.active.where(id: repository_ids).pluck(:id, :owner_id).to_h)

      validation_result_by_owner_id = T.let({}, T::Hash[Integer, T::Boolean])
      repository_owner_ids.values.uniq.each do |owner_id|
        validation_result_by_owner_id.merge!(owner_id => should_perform_compression?(owner_id))
      end

      repo_ids_to_process = T.let([], T::Array[[Integer, Integer]])
      GitHub.logger.info(
        "Repository data compression job processing repositories.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.repository_ids": repository_ids,
      )
      repository_ids.each do |repo_id|
        owner_id = T.must(repository_owner_ids[repo_id])
        validation_result = validation_result_by_owner_id[owner_id]
        repo_ids_to_process << [repo_id, owner_id] if validation_result
      end

      repo_ids_to_process.each do |repository_id, owner_id|
        features.each do |feature|
          AlertDataCompressionJob.perform_later(feature:, repository_id:, owner_id:, dry_run:)
        end
      end
    end

    sig { params(args: T::Array[T.untyped], options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    private

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def should_perform_compression?(owner_id)
      owner = ::User.find_by!(id: owner_id)

      return false unless FeatureFlagHelper.run_data_compression?(owner)

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

    class Session
      extend T::Sig

      SESSION_LOCK_DURATION_IN_DAYS = 7
      SESSION_KEY = T.let("#{RepositoryDataCompressionJob.name}", String)

      sig { returns(T.nilable(String)) }
      def self.current
        SecurityCenter::KV.store.get(SESSION_KEY).value { nil }
      end

      sig { returns(T.nilable(String)) }
      def self.lock!
        session_id = SecureRandom.uuid
        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.set(SESSION_KEY, session_id, expires: SESSION_LOCK_DURATION_IN_DAYS.days.from_now)
        end
        session_id
      end
    end
  end
end
