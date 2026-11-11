# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    module QueueStrategies

      # QueueShuffle randomizes the list of queues each time.
      #
      # Shuffling is applied to the queues returned by the next strategy.
      class QueueShuffle
        sig { params(queues: T::Array[String], tags: T::Hash[String, String], next_strategy: T.proc.params(arg0: T::Array[String], arg1: T::Hash[String, String]).returns(T::Array[String])).returns(T::Array[String]) }
        def call(queues, tags, next_strategy)
          queues = next_strategy.call(queues, tags)
          queues = queues.shuffle if shuffle_enabled?
          queues
        end

        protected

        sig { returns(T::Boolean) }
        def shuffle_enabled?
          FeatureFlag.vexi.enabled?("use_queue_shuffle_#{GitHub.role}", default: false)
        end
      end
    end
  end
end
