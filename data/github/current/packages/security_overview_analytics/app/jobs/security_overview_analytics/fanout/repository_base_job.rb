# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    class RepositoryBaseJob < BatchedJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
      extend T::Helpers
      include GitHub::Memoizer
      include FanoutThrottler
      include BatchedJobThrottler

      abstract!

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 15.minutes, key: ->(job) do
        repository_id = job.arguments.dig(0, :repository_id)
        DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
      end

      resolve_tenant_context do |args|
        repo_id = args[:repository_id]
        ::Repositories::Public.resolve_tenant(id: repo_id)
      end

      around_enqueue do |job, block|
        if job.repository_id <= 0
          raise ArgumentError.new("Invalid repository_id input.")
        end

        block.call
      rescue ArgumentError
        job.clear_lock
        raise
      end

      around_perform do |_, block|
        next unless should_perform?
        block.call
        GitHub.dogstats.increment("security_overview_analytics.repository_fanout.processed", tags: all_stats_tags)
      end

      sig { params(args: T::Array[T.untyped], options: T.untyped).void }
      def finalize_batch(*args, **options)
        # Because the hash lock is based on shared params between batches,
        # we need to release the hash lock before enqueuing the next batch.
        clear_lock
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        tags = super
        tags << "source_event:#{source_event}" if source_event.present?
        tags
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.source_event": source_event,
          "gh.security_overview_analytics.job.last_session_locked_at": arguments.dig(0, :last_session_locked_at),
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

      sig { returns(Integer) }
      memoize def repository_id
        arguments.dig(0, :repository_id) || 0
      end

      sig { returns(T.nilable(::Repository)) }
      memoize def repository
        ::Repository.find_by(id: repository_id)
      end

      sig { returns(T.nilable(Time)) }
      memoize def last_session_locked_at
        arguments.dig(0, :last_session_locked_at)
      end

      sig { abstract.returns(String) }
      def source_event; end

      sig { overridable.returns(T::Boolean) }
      def should_perform?
        if repository.nil?
          log_fanout_stopped(:repository_not_found)
          return false
        end

        true
      end

      sig { params(reason: Symbol).void }
      def log_fanout_stopped(reason)
        GitHub.logger.info(
          "Repository fanout stopped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.reason": reason
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.repository_fanout.stopped",
          tags: all_stats_tags + ["reason:#{reason}"]
        )
      end
    end
  end
end
