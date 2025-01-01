# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class BusinessJob < TenantBaseJob
      include FanoutThrottler

      queue_as :security_overview_analytics_business_initialization

      locked_by timeout: 15.minutes, key: -> (job) do
        DEFAULT_LOCK_STRINGIFY_PROC.call([job.business_id, job.type_argument])
      end

      sig do
        override
          .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
          .returns(T.all(T::Enumerable[T.untyped], Object))
      end
      def fetch_batch(*args, offset_id:, **kwargs)
        if type_argument == Initialization::Type::Organizations.serialize
          business
            .organizations
            .where(::Organization.arel_table[:id].gt(offset_id))
            .order(:id)
            .limit(1000)
            .select(:id)
        elsif type_argument == Initialization::Type::Users.serialize
          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business)
          return [] unless feature.feature_available_for_user_repositories?
          feature.list_enterprise_users_offset(offset_id: offset_id, per_page: 1000)
        else
          raise ArgumentError, "Invalid initialization type: #{type_argument}"
        end
      end

      sig { override.params(args: T.untyped, item: ::User, type: T.nilable(String), kwargs: T.untyped).void }
      def process_item(*args, item:, type: nil, **kwargs)
        if [Initialization::Type::Organizations.serialize, Initialization::Type::Users.serialize].include?(type_argument)
          initialization = SecurityOverviewAnalytics::Initialization.for(item)
          if initialization.any_initialized?
            SecurityOverviewAnalytics::ReconciliationScheduler.run_for(item)
          else
            initialization.enqueue
          end
        else
          raise ArgumentError, "Invalid initialization type: #{type_argument}"
        end
      end

      sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
      def item_id(*args, item:, **kwargs)
        item.id
      end

      sig { override.returns(SecurityOverviewAnalytics::Initialization) }
      memoize def initialization
        SecurityOverviewAnalytics::Initialization.for(business)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        kwargs = arguments.first || {}
        super.merge({
          "gh.business.id" => business_id,
          "gh.business.slug" => business.try(:slug),
          "gh.security_overview_analytics.initialization_type" => type_argument,
        })
      end

      sig { returns(String) }
      memoize def type_argument
        (arguments[0] || {})[:type] || Initialization::Type::Organizations.serialize
      end

      sig { returns(Integer) }
      memoize def business_id
        (arguments[0] || {}).fetch(:business_id)
      end

      sig { returns(::Business) }
      memoize def business
        Business.find(business_id)
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        # While we can enqueue reconciliation on a previous initialized organization or user,
        # it should be rare and not all organizations/users are guaranteed to be previously initialized.
        #
        # Because of the reason above, we only check on initialization job queue instead for fanout throttling.
        [OrganizationJob, UserJob]
      end
    end
  end
end
