# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    module QueueStrategies

      # QueueMemoization is a strategy that caches the result of the next strategy in-memory
      # for a period of time.
      class QueueMemoization
        DEFAULT_EXPIRATION = 30.seconds

        sig { params(expiration: ActiveSupport::Duration).void }
        def initialize(expiration: DEFAULT_EXPIRATION)
          @expiration = expiration
          @value = nil
          @expires_at = nil
        end

        sig { params(queues: T::Array[String], tags: T::Hash[String, String], next_strategy: T.proc.params(arg0: T::Array[String], arg1: T::Hash[String, String]).returns(T::Array[String])).returns(T::Array[String]) }
        def call(queues, tags, next_strategy)
          if memoize_queues?
            if @expires_at.nil? || Time.now > @expires_at
              @value = next_strategy.call(queues, tags).dup
              @expires_at = Time.now + @expiration
            end
            @value.dup
          else
            next_strategy.call(queues, tags)
          end
        end

        protected

        sig { returns(T::Boolean) }
        def memoize_queues?
          # default true, we prefer to always memoize unless explicitly disabled
          FeatureFlag.vexi.enabled?("use_queue_memoization_#{GitHub.role}", default: true)
        end
      end
    end
  end
end
