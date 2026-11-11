# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Specializes `BaseProcessor` for consumers that process only one message
    # per invocation. This is the recommended base class for most processors.
    class SingleMessageProcessor < BaseProcessor
      extend T::Helpers
      extend ActiveSupport::DescendantsTracker

      abstract!

      sig(:final) { override.returns(T::Boolean) }
      def batching? = false

      sig(:final) { override.params(batch: T.untyped).returns(T.anything) }
      def process_batch(batch)
        # Implements the abstract hook for batched message processing as a no-op,
        # because subclasses will implement `process_message` instead.
      end
    end
  end
end
