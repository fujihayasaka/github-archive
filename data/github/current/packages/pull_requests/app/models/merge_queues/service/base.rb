# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class Base
      include GitHub::Memoizer

      sig { params(repository: Repository, branch: String, merge_queue: T.nilable(MergeQueue)).void }
      def initialize(repository, branch, merge_queue = nil)
        @repository = repository
        @branch = branch
        @merge_queue = T.let(
          merge_queue || MergeQueue.find_by(repository: @repository, branch: @branch),
          T.nilable(MergeQueue)
        )
      end

      private

      sig { returns(Factory) }
      memoize def factory
        Factory.new(@repository, T.must(@merge_queue))
      end

      sig { returns(IConfiguration) }
      memoize def configuration
        factory.configuration
      end

      sig { returns(CommandActionLogger) }
      memoize def command_without_status_check_models
        CommandActionLogger.new(Command.new(
          T.must(@merge_queue),
          @repository,
          factory.merge_queue_entry_models,
        ))
      end

      sig { returns(CommandActionLogger) }
      memoize def command_with_status_check_models
        CommandActionLogger.new(Command.new(
          T.must(@merge_queue),
          @repository,
          factory.merge_queue_entry_models,
          factory.retryable_check_models,
        ))
      end

      sig { params(merge_queue_entries: T::Array[MergeQueueEntry]).void }
      def notify_websockets!(merge_queue_entries = [])
        @merge_queue&.notify_socket_subscribers
        pull_requests = merge_queue_entries.map(&:pull_request).compact.uniq
        pull_requests.each { |pull_request| @merge_queue&.notify_subscribers(pull_request:) }
      end

      sig { void }
      def request_execution!
        MergeQueues.execute!(@repository, @branch)
      end

      sig do
        type_parameters(:R).
          params(block: T.proc.returns(T.type_parameter(:R))).
          returns(T.type_parameter(:R))
      end
      def with_merge_mutex(&block)
        T.must(@merge_queue).merge_mutex.lock(&block)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def configuration_for_logs
        {
          max_wait_for_min_merge_entries_size: configuration.max_wait_for_min_merge_entries_size,
          min_merge_entries_size: configuration.min_merge_entries_size,
          max_merge_entries_size: configuration.max_merge_entries_size,
          max_concurrency: configuration.max_concurrency,
          max_attempts: configuration.max_attempts,
          actor_controlled_merging: configuration.actor_controlled_merging,
          check_response_timeout: configuration.check_response_timeout,
          grouping_strategy: configuration.grouping_strategy.serialize,
          merge_method: configuration.merge_method.serialize,
        }
      end
    end
  end
end
