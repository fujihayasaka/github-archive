# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class TenantBaseJob < TimedJob
      abstract!

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      RETRYABLE_ERRORS = T.let([
        ActiveRecord::RecordNotFound, # replication lag
        Freno::Error
      ], T::Array[T.class_of(StandardError)])
      T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

      around_enqueue do |job, block|
        next block.call unless job.is_first_job?

        # Always enqueue the job if it was enqueued for retry.
        next block.call if job.exception_executions.present?

        type_arg = job.arguments.dig(0, :type)
        if type_arg.present?
          type = Initialization::Type.deserialize(type_arg)
          if job.initialization.initialized?(type:)
            clear_lock
            next
          end
          block.call
        elsif job.initialization.any_uninitialized?
          block.call
        else
          clear_lock
        end
      end

      before_perform do |job|
        next unless job.is_first_job?

        type_arg = job.arguments.dig(0, :type)
        if type_arg.present?
          type = Initialization::Type.deserialize(type_arg)
          next if job.initialization.initialized?(type:)
          ThrottleHelper.throttle_kv_writes_with_fallback do
            job.initialization.set_type_to_initialized(type:)
          end
        elsif job.initialization.any_uninitialized?
          ThrottleHelper.throttle_kv_writes_with_fallback do
            job.initialization.set_all_to_initialized
          end
        end
      end

      sig { abstract.returns(Initialization) }
      def initialization; end

      INITIALIZATION_EVENT = T.let("security_overview_analytics.initialization", String)

      sig { params(source_event: String).returns(T::Boolean) }
      def self.is_initialization_event?(source_event)
        INITIALIZATION_EVENT == source_event
      end

      sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
      def item_id(*args, item:, **kwargs)
        item
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({ app: "github-security-center" })
      end

      sig { returns(T::Boolean) }
      memoize def is_first_job?
        (arguments[0] || {}).fetch(:offset_id, 0).zero?
      end
    end
  end
end
