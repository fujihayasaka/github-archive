# typed: strict
# frozen_string_literal: true

module GH
  module Context
    # Interface for request-scoped data that needs cleanup when the context exits.
    #
    # Implement this interface and store instances in `GH.context.data[:your_key]`.
    # The `on_context_exit` method will be called automatically when the context
    # is popped, allowing cleanup or metric emission.
    #
    # Example:
    #   class MyRequestData
    #     include GH::Context::ScopedData
    #
    #     def initialize
    #       @items = []
    #     end
    #
    #     def add(item)
    #       @items << item
    #     end
    #
    #     def on_context_exit
    #       # emit metrics, cleanup, etc.
    #     end
    #   end
    #
    #   # Usage in domain code:
    #   data = GH.context.data[:my_data] ||= MyRequestData.new
    #   data.add(something)
    #
    module ScopedData
      extend T::Helpers
      interface!

      # Called when the GH::Context is about to be popped.
      # Use for cleanup, metric emission, or other end-of-request tasks.
      sig { abstract.void }
      def on_context_exit
      end
    end
  end
end
