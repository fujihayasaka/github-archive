# typed: strict
# frozen_string_literal: true

require_relative "../../models/security_center/k_v"

module SecurityCenter
  class OrganizationReconciliationJob < BatchedJob
    extend T::Sig
    include GitHub::Memoizer
    include FanoutThrottler
    include BatchedJobThrottler

    queue_as :security_center_reconciliation

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

    RECONCILIATION_EVENT = T.let("security_center.org.reconciliation", String)
    BACKFILL_EVENT = T.let("security_center.org.backfill", String)
    NON_INCREMENTAL_EVENTS = T.let([
      RECONCILIATION_EVENT,
      BACKFILL_EVENT,
      SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT,
      SecurityCenter::BusinessReconciliationJob::BACKFILL_EVENT
    ], T::Array[String])

    sig { params(source_event: String).returns(T::Boolean) }
    def self.is_reconciliation_event?(source_event)
      RECONCILIATION_EVENT == source_event
    end

    around_enqueue do |job, block|
      organization_id = job.arguments.dig(0, :organization_id)
      offset_item_id = job.arguments.dig(0, :offset_item_id) || 0
      session_id = job.arguments.dig(0, :session_id)
      source_event = job.arguments.dig(0, :source_event)

      if session_id.nil?
        session_id = SecureRandom.uuid
        job.arguments.first.merge!(session_id: session_id)
      end

      kv_helper = KvHelper.new(organization_id)
      kv_session = kv_helper.session_lock

      if kv_session == session_id
        # we still own this lock; continue
        next block.call
      end

      if kv_session.nil?
        # the lock is free; take it
        kv_helper.session_lock = session_id
        next block.call
      end

      if offset_item_id.zero? && source_event.present? && NON_INCREMENTAL_EVENTS.exclude?(source_event)
        # The lock exists, but it's not ours; steal it. This can be one of two cases
        # a) Reconciliation was completed recently, but we're forcing a new run (due to change event or "force").
        # b) There is an active reconciliation or backfill session, and we're preempting it.
        # Note that lock stealing is only allowed for the first batch of a session; you can't reacquire a stolen lock.
        kv_helper.session_lock = session_id
        GitHub.dogstats.increment("security_center.reconciliation_job.interrupted.count", tags: job.all_stats_tags)
        next block.call
      end

      # the lock is not available, and we can't steal it; abort
      GitHub.dogstats.increment("security_center.reconciliation_job.skip_recent.count", tags: job.all_stats_tags)
    end

    sig do
      params(
        args: T.untyped,
        organization_id: Integer,
        offset_item_id: Integer,
        kwargs: T.untyped,
      )
      .returns(T::Array[Repository])
    end
    def next_batch(*args, organization_id:, offset_item_id:, **kwargs)
      # Fetch a batch of repositories for this org. This data is canonical, but it may be out of sync with Security Center
      # data (for example, if a repo has been added to or removed from the org).
      #
      # We used to get repositories from below model but it hit multiple timeouts on large orgs as it uses primary key to do
      # table scan.
      # repositories = org.repositories.
      #   where("id > ?", last_repository_id).
      #   order(:id).
      #   limit(DEFAULT_BATCH_SIZE)
      #
      # We now instead force index on index_repositories_on_owner_id_and_name_and_active to filter down by owner_id
      repo_query = Arel.sql(<<-SQL, owner_id: organization_id, last_repository_id: offset_item_id, limit: Arel.sql(BATCH_SIZE.to_s))
        SELECT id FROM repositories USE INDEX (index_repositories_on_owner_id_and_name_and_active)
        WHERE owner_id = :owner_id AND active = 1 AND id > :last_repository_id
        ORDER BY id ASC
        LIMIT :limit
      SQL
      Repository.find_by_sql(repo_query)
    end

    sig do
      params(
        records: T::Array[Repository],
        args: T.untyped,
        organization_id: Integer,
        offset_item_id: Integer,
        source_event: T.nilable(String),
        kwargs: T.untyped,
      )
      .void
    end
    def process_batch(records, *args, organization_id:, offset_item_id:, source_event:, **kwargs)
      records.each do |repo|
        GitHub.dogstats.increment("security_center.reconciliation_job.fanout.count", tags: all_stats_tags)
        repo_id = T.must(repo.id)
        queue_update(repo_id, source_event)
      end

      # Find any security center records within this range to identify orphaned repositories.
      reconciled_repository_ids = RepositorySecurityCenterConfig
        .where(owner_id: organization_id)
        .where("repository_id > ?", offset_item_id)
        .order(:repository_id)
        .limit(BATCH_SIZE)
        .pluck(:repository_id)
      batch_ids = records.map(&:id)

      orphaned_ids = (reconciled_repository_ids - batch_ids)
      orphaned_ids.each do |repo_id|
        GitHub.dogstats.increment("security_center.reconciliation_job.fanout.count", tags: all_stats_tags + ["orphaned:true"])
        queue_update(repo_id, source_event)
      end

      GitHub.logger.info(
        "Batch completed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.job.batch_ids": batch_ids,
        "gh.security_center.job.orphaned_ids": orphaned_ids,
      )
    end

    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [RepositoryReconciliationJob, RepositorySyncJob]
    end

    protected

    sig { returns(T::Array[String]) }
    def stats_tags
      tags = []
      source_event = arguments.dig(0, :source_event)
      tags << "source_event:#{source_event}" if source_event.present?
      tags
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.org.id": organization&.id,
        "gh.org.login": organization&.display_login,
        "gh.security_center.source_event": arguments.dig(0, :source_event),
        "gh.security_center.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_center.job.initial_start": arguments.dig(0, :initial_start),
        "gh.security_center.job.progress": arguments.dig(0, :progress),
        "gh.security_center.job.session_id": arguments.dig(0, :session_id),
      })
    end

    private

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      organization_id = arguments.dig(0, :organization_id)
      Organization.find_by(id: organization_id)
    end

    sig { params(repository_id: Integer, source_event: T.nilable(String)).void }
    def queue_update(repository_id, source_event)
      source_event ||= RECONCILIATION_EVENT
      is_reconciliation =
        OrganizationReconciliationJob.is_reconciliation_event?(source_event) ||
        BusinessReconciliationJob.is_reconciliation_event?(source_event)

      if is_reconciliation
        RepositoryReconciliationJob.perform_later(repository_id:, source_event:)
      else
        SecurityFeatures.all.each do |feature_type|
          ::SecurityCenter::RepositorySyncJob.perform_later(
            repository_id:,
            feature_type:,
            source_event:,
          )
        end
      end
    end

    class KvHelper
      extend T::Sig

      sig { returns(String) }; attr_reader :session_key

      sig { params(organization_id: Integer).void }
      def initialize(organization_id)
        @session_key = T.let("#{OrganizationReconciliationJob.name}:#{organization_id}", String)
      end

      sig { returns(T.nilable(String)) }
      def session_lock
        SecurityCenter::KV.store.get(session_key).value { nil }
      end

      sig { params(value: T.nilable(String)).void }
      def session_lock=(value)
        ActiveRecord::Base.connected_to(role: :writing) do
          if value.present?
            SecurityCenter::KV.store.set(session_key, value, expires: 7.days.from_now)
          else
            SecurityCenter::KV.store.del(session_key)
          end
        end
      end

      sig { returns(T.nilable(Time)) }
      def session_ttl
        SecurityCenter::KV.store.ttl(session_key).value { nil }
      end
    end
  end
end
