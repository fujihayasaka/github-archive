# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class BusinessReconciliationJob < BatchedJob
    include GitHub::Memoizer
    include FanoutThrottler
    include BatchedJobThrottler

    queue_as :security_center_reconciliation

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    EntityType = Serializers::BusinessReconciliationJobEntityType::EntityType

    # The base BatchedJob adds several parameters that effectively make every enqueue unique.
    # Limit this to only the input parameters. Requires manually clearing the lock in finalize_batch.
    locked_by timeout: 15.minutes, key: ->(job) do
      business_id = job.arguments.dig(0, :business_id)
      entity_type = job.arguments.dig(0, :entity_type) || EntityType::Organization
      DEFAULT_LOCK_STRINGIFY_PROC.call([business_id, entity_type])
    end

    RECONCILIATION_EVENT = T.let("security_center.business.reconciliation", String)
    BACKFILL_EVENT = T.let("security_center.business.backfill", String)

    sig { params(source_event: String).returns(T::Boolean) }
    def self.is_reconciliation_event?(source_event)
      RECONCILIATION_EVENT == source_event
    end

    sig do
      params(
        args: T.untyped,
        business_id: Integer,
        offset_item_id: Integer,
        entity_type: EntityType,
        kwargs: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(*args, business_id:, offset_item_id:, entity_type: EntityType::Organization, **kwargs)
      if business.nil?
        GitHub.logger.warn(
          "No business found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
        )
        return []
      end

      case entity_type
      when EntityType::Organization
        T.must(business)
          .organizations
          .where(::Organization.arel_table[:id].gt(offset_item_id))
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
      when EntityType::User
        feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(T.must(business))
        return [] unless feature.feature_available_for_user_repositories?
        feature.list_enterprise_users_ids_offset(offset_id: offset_item_id, per_page: BATCH_SIZE)
      else
        T.absurd(entity_type)
      end
    end

    sig do
      params(
        records: T::Array[Integer],
        args: T.untyped,
        business_id: Integer,
        source_event: T.nilable(String),
        kwargs: T.untyped,
      )
      .void
    end
    def process_batch(records, *args, business_id:, source_event: nil, **kwargs)
      records.each do |id|
        enqueue_result = SecurityCenter::OwnerReconciliationJob.perform_later(owner_id: id, source_event: source_event)
        GitHub.dogstats.increment("security_center.business_reconciliation_job.fanout.count", tags: all_stats_tags + ["enqueued:#{!!enqueue_result}"])
      end

      GitHub.logger.info(
        "Batch completed.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.job.batch_ids": records,
      )
    end

    sig { params(args: T::Array[T.untyped], options: T.untyped).void }
    def finalize_batch(*args, **options)
      # Because the hash lock is on the `business_id` and `entity_type` parameters, enqueues for subsequent batches would fail.
      # Release here before the next batch is enqueued.
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
      [OwnerReconciliationJob]
    end

    protected

    sig { returns(T::Array[String]) }
    def stats_tags
      tags = []
      tags << "source_event:#{source_event}" if source_event.present?
      tags << "entity_type:#{entity_type.serialize}"
      tags
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.business.id": arguments.dig(0, :business_id),
        "gh.business.name": business&.name,
        "gh.security_center.source_event": source_event,
        "gh.security_center.entity_type": entity_type,
        "gh.security_center.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_center.job.initial_start": arguments.dig(0, :initial_start),
        "gh.security_center.job.progress": arguments.dig(0, :progress),
      })
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    private

    sig { returns(T.nilable(Business)) }
    memoize def business
      business_id = arguments.dig(0, :business_id)
      Business.find_by(id: business_id)
    end

    sig { returns(T.nilable(String)) }
    memoize def source_event
      arguments.dig(0, :source_event)
    end

    sig { returns(EntityType) }
    memoize def entity_type
      arguments.dig(0, :entity_type) || EntityType::Organization
    end
  end
end
