# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class Consumer
      def initialize(client:)
        @client = client
        @closed = false
      end

      # Public: Yields successive messages.
      #
      # block - a Proc to process each message
      def each_message(&block)
        while !closed?
          message = client.peek_lock_message(timeout: 1)

          # nil message means HTTP request timed out because there are no messages - we should loop again
          next if message.nil?

          block.call(message.body)
          client.delete_message(message)
        end
      end

      def close
        @closed = true
      end

      private

      attr_reader :client

      def closed?
        !!@closed
      end
    end
  end
end
