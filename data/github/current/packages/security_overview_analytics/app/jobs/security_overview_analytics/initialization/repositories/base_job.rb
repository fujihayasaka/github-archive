# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class BaseJob < ApplicationJob
        extend T::Sig
        extend T::Helpers
        include GitHub::Memoizer

        abstract!

        use_replicas \
          ::ApplicationRecord::Configurations,
          ::ApplicationRecord::Mysql1,
          ::ApplicationRecord::Repositories,
          ::ApplicationRecord::SecurityOverviewAnalytics

        retry_on_dirty_exit
        retry_on_recoverable_exceptions
        retry_on \
          Freno::Error,
          ActiveRecord::RecordNotFound,
          ActiveRecord::Deadlocked,
          wait: :polynomially_longer,
          attempts: 6,
          jitter: 0.15

        locked_by timeout: 15.minutes, key: -> (job) do
          DEFAULT_LOCK_STRINGIFY_PROC.call([job.repository_id])
        end

        around_perform do |_, block|
          if repository.deleted?
            report_skipped("repository_deleted")
            next
          end

          unless TenantValidationHelper.is_owner_in_scope?(owner)
            report_skipped("tenant_not_in_scope")
            next
          end

          block.call
        end

        sig { abstract.params(repository_id: Integer).void }
        def perform(repository_id:); end

        sig { returns(T.nilable(::Business)) }
        memoize def business
          BusinessResolver.resolve_for(owner)
        end

        sig { returns(::User) }
        memoize def owner
          T.must(repository.owner)
        end

        sig { returns(::Repository) }
        memoize def repository
          ::Repositories::Public.get_active_or_deleted!(repository_id)
        end

        sig { returns(Integer) }
        memoize def repository_id
          (arguments[0] || {}).fetch(:repository_id)
        end

        sig { returns(Integer) }
        memoize def date_id
          ::SecurityOverviewAnalytics::Date.id_from_date(now.to_date)
        end

        sig { returns(Time) }
        memoize def now
          Time.current.utc
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def failbot_context
          super.merge({ app: "github-security-center" })
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def logging_context
          owner_type = owner.is_a?(::Organization) ? "org" : "user"
          owner_info = {
            "gh.repo.owner.id": owner.id,
            "gh.repo.owner.login": owner.display_login,
            "gh.#{owner_type}.id": owner.id,
            "gh.#{owner_type}.login": owner.display_login,
          }

          super.merge({
            "gh.business.id": business.try(:id),
            "gh.business.slug": business.try(:slug),
            "gh.repo.id": repository_id,
            "gh.repo.name": repository.name,
            **owner_info,
          })
        end

        private

        sig { params(reason: String).void }
        def report_skipped(reason)
          GitHub.logger.info(
            "Initialization skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": reason,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.initialization.skipped",
            tags: all_stats_tags + [
              "reason:#{reason.parameterize.underscore}"
            ]
          )
        end
      end
    end
  end
end
