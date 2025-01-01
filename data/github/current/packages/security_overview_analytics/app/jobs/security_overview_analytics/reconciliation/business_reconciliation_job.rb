# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class BusinessReconciliationJob < BatchedJob
      extend T::Sig
      include GitHub::Memoizer
      include FanoutThrottler

      queue_as :security_overview_analytics_tenant_reconciliation

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      # The base BatchedJob adds several parameters that effectively make every enqueue unique.
      # Limit this to only the input parameters. Requires manually clearing the lock in finalize_batch.
      locked_by timeout: 15.minutes, key: ->(job) do
        business_id = job.arguments.dig(0, :business_id)
        entity_type = job.arguments.dig(0, :entity_type) || EntityType::Organization
        DEFAULT_LOCK_STRINGIFY_PROC.call([business_id, entity_type])
      end

      RECONCILIATION_EVENT = T.let("security_center.business.reconciliation", String)

      EntityType = SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType

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
        return [] unless should_reconcile?

        case entity_type
        when EntityType::Organization
          T.must(business)
            .organizations
            .where(::Organization.arel_table[:id].gt(offset_item_id))
            .order(:id)
            .limit(BATCH_SIZE)
            .pluck(:id)
        when EntityType::User
          if FeatureFlagHelper.check_for_user_repositories?(T.must(business))
            ghas_instance = ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(T.must(business))
            ghas_instance.list_enterprise_users_ids_offset(offset_id: offset_item_id, per_page: BATCH_SIZE)
          else
            if business&.enterprise_managed? && business&.external_provider_enabled?
              ExternalIdentity
                .by_provider(business&.external_provider)
                .where("user_id > ?", offset_item_id)
                .order(:user_id)
                .limit(BATCH_SIZE)
                .pluck(:user_id)
            elsif GitHub.enterprise?
              User
                .where(type: "User")
                .where("id > ?", offset_item_id)
                .order(:id)
                .limit(BATCH_SIZE)
                .pluck(:id)
            else
              []
            end
          end
        else
          T.absurd(entity_type)
        end
      end

      sig do
        params(
          records: T::Array[Integer],
          args: T.untyped,
          business_id: Integer,
          kwargs: T.untyped,
        )
        .void
      end
      def process_batch(records, *args, business_id:, **kwargs)
        records.each do |id|
          enqueue_result = if entity_type == EntityType::Organization
            Reconciliation::OrganizationReconciliationJob.perform_later(organization_id: id)
          else
            # OwnerReconciliationJob will replace OrganizationReconciliationJob in follup PRs
            Reconciliation::OwnerReconciliationJob.perform_later(owner_id: id)
          end
        end
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
        [OwnerReconciliationJob, OrganizationReconciliationJob]
      end

      protected

      sig { returns(T::Boolean) }
      def should_reconcile?
        if business.nil?
          GitHub.logger.warn(
            "No business found.",
            "code.namespace": self.class.name,
            "code.function": __method__,
          )
          return false
        end

        unless Initialization.for(T.must(business)).initialized?(type:)
          GitHub.logger.info(
            "Business reconciliation skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": "Tenant not initialized."
          )

          GitHub.dogstats.increment(
            "security_overview_analytics.business_reconciliation.skipped",
            tags: all_stats_tags + ["reason:tenant_not_initialized"]
          )
          return false
        end
        true
      end

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
          "gh.security_overview_analytics.source_event": source_event,
          "gh.security_overview_analytics.reconciliation.type": entity_type,
          "gh.security_overview_analytics.offset_item_id": arguments.dig(0, :offset_item_id),
          "gh.security_overview_analytics.initial_start": arguments.dig(0, :initial_start),
          "gh.security_overview_analytics.progress": arguments.dig(0, :progress),
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
        Business.find_by!(id: business_id)
      end

      sig { returns(T.nilable(String)) }
      memoize def source_event
        arguments.dig(0, :source_event)
      end

      sig { returns(EntityType) }
      memoize def entity_type
        arguments.dig(0, :entity_type) || EntityType::Organization
      end

      sig { returns(Initialization::Type) }
      memoize def type
        if entity_type == EntityType::User
          Initialization::Type::Users
        else
          Initialization::Type::Organizations
        end
      end
    end
  end
end
