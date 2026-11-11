# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class Consumer
      sig { params(client: T.any(QueueClient, SubscriptionClient)).void }
      def initialize(client:)
        @client = T.let(client, T.any(QueueClient, SubscriptionClient))
        @closed = T.let(false, T::Boolean)
      end

      # Public: Yields successive messages.
      #
      # block - a Proc to process each message
      sig { params(block: T.proc.params(arg0: String).void).void }
      def each_message(&block)
        while !closed?
          message = client.peek_lock_message(timeout: 1)

          # nil message means HTTP request timed out because there are no messages - we should loop again
          next if message.nil?

          block.call(message.body)
          client.delete_message(message)
        end
      end

      sig { void }
      def close
        @closed = true
      end

      private

      sig { returns(T.any(QueueClient, SubscriptionClient)) }
      attr_reader :client

      sig { returns(T::Boolean) }
      def closed?
        !!@closed
      end
    end
  end
end
