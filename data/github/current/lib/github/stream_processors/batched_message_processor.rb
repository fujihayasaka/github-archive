# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Specializes `BaseProcessor` for consumers that process several messages
    # per invocation. This class should only be used when there is a clear need
    # for batching.
    class BatchedMessageProcessor < BaseProcessor
      extend T::Helpers
      extend ActiveSupport::DescendantsTracker

      abstract!

      sig(:final) { override.returns(T::Boolean) }
      def batching? = true

      # Provides a default implementation of `process_batch` that ultimately just calls
      # the `process_message` hook in a loop.
      #
      # The benefit of using this default implementation is that you inherit standard telemetry
      # and heartbeating; if you choose to override this hook you must provide those behaviors
      # yourself.
      #
      # If you do override this hook, then you must still implement `process_message`, but you
      # can do so as a no-op (assuming that you will processage messages directly within the override
      # of this method).
      sig { override.overridable.params(batch: T::Array[Hydro::Consumer::ConsumerMessage]).returns(T.anything) }
      def process_batch(batch)
        @current_batch = T.let(batch, T.nilable(T::Array[Hydro::Consumer::ConsumerMessage]))
        run_callbacks :batch do
          time("process_batch") do
            batch.each do |consumer_message|
              safe_trigger_heartbeat
              message = process_consumer_message(consumer_message)
              consumer.mark_message_as_processed(consumer_message) if message.processed?
            end
          end
        end
      end
    end
  end
end
