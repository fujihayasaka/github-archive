# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class UserJob < TenantBaseJob
      include FanoutThrottler

      queue_as :security_overview_analytics_tenant_initialization

      locked_by timeout: 15.minutes, key: -> (job) do
        DEFAULT_LOCK_STRINGIFY_PROC.call([job.user_id])
      end

      sig do
        override
          .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
          .returns(T.all(T::Enumerable[T.untyped], Object))
      end
      def fetch_batch(*args, offset_id:, **kwargs)
        return [] unless user_id

        ::Repository
          .where(active: true, owner_id: user_id)
          .where(::Repository.arel_table[:id].gt(offset_id))
          .order(:id)
          .limit(1000)
          .pluck(:id)
      end

      sig { override.params(args: T.untyped, item: T.untyped, type: T.nilable(String), kwargs: T.untyped).void }
      def process_item(*args, item:, type: nil, **kwargs)
        repository_id = T.let(item, Integer)

        # If we are initializing a specific type, only initialize that type.
        # Otherwise initialize all types.
        types_to_initialize = initialization.initialization_types

        types_to_initialize &= [Initialization::Type.deserialize(type)] if type.present?

        types_to_initialize.each do |type|
          case type
          when Initialization::Type::FeatureEnablement
            Initialization::Repositories::FeatureEnablementJob.perform_later(repository_id:)
          when Initialization::Type::RepositoryMetadata
            Initialization::Repositories::RepoMetadataJob.perform_later(repository_id:)
          when Initialization::Type::CodeScanningAlert
            # Not supported for EMU, however keeping for Sorbet exhaustiveness checking.
            next
          when Initialization::Type::SecretScanningAlert
            Initialization::Repositories::SecretScanningAlertsJob.perform_later(repository_id:)
          when Initialization::Type::DependabotAlerts
            # Not supported for EMU, however keeping for Sorbet exhaustiveness checking.
            next
          when Initialization::Type::Organizations, Initialization::Type::Users
            # These types are not handled at the repository level.
            next
          when Initialization::Type::Unknown
            # valid_values should never include Unknown.
            # However, without having a case for it, Sorbet's exhaustiveness checking does not work.
          else
            T.absurd(type)
          end
        end

        GitHub.logger.info(
          "Repository initializations enqueued.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
        )
      end

      sig { override.returns(SecurityOverviewAnalytics::Initialization) }
      memoize def initialization
        SecurityOverviewAnalytics::Initialization.for(user)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        kwargs = arguments.first || {}
        context = {
          "gh.user.id" => user_id,
          "gh.security_overview_analytics.initialization_type" => kwargs.try(:type) || "all",
        }

        context["gh.user.login"] = user.display_login if user_id.present?
        super.merge(context)
      end

      sig { returns(T.nilable(Integer)) }
      memoize def user_id
        (arguments[0] || {}).fetch(:user_id, nil)
      end

      sig { returns(::User) }
      memoize def user
        ::User.find(T.must(user_id))
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        # If any of the below job queue is being throttled, delay the entire batch.
        [
          Repositories::RepoMetadataJob,
          Repositories::FeatureEnablementJob,
          Repositories::DependabotAlertsJob,
          Repositories::CodeScanningAlertsJob,
          Repositories::SecretScanningAlertsJob,
        ]
      end
    end
  end
end
