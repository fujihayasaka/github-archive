# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class BaseBatchedJob < BatchedJob
        extend T::Helpers
        include GitHub::Memoizer
        abstract!

        retry_on_dirty_exit
        retry_on_recoverable_exceptions
        retry_on(
          ActiveRecord::Deadlocked,
          ActiveRecord::RecordNotFound,
          Freno::Error,
          wait: :polynomially_longer,
          attempts: 6,
          jitter: 0.15,
        )

        use_replicas(
          ApplicationRecord::Configurations,
          ApplicationRecord::Mysql1,
          ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::Repositories,
        )

        around_enqueue do |job, block|
          repository_id = job.arguments.dig(0, :repository_id)
          if repository_id.blank?
            clear_lock
            raise ArgumentError.new("Missing repository_id.")
          end

          block.call
        end

        around_perform do |job, block|
          next unless job.should_initialize?
          block.call
        end

        sig { abstract.returns(T::Boolean) }
        def should_initialize?; end

        private

        sig { returns(Integer) }
        memoize def repository_id
          T.must(T.let(arguments.dig(0, :repository_id), T.nilable(Integer)))
        end

        sig { returns(::Repository) }
        memoize def repository
          ::Repositories::Public.get_active_or_deleted!(repository_id)
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def logging_context
          super.merge({
            "gh.repo.id" => repository_id,
            "gh.repo.name" => repository.name,
            "gh.repo.owner.id" => repository.owner_id,
          })
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def failbot_context
          super.merge({ app: "github-security-center" })
        end
      end
    end
  end
end
