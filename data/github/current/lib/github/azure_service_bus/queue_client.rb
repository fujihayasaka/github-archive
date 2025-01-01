# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class QueueClient
      DEFAULT_TIMEOUT = 60

      def initialize(queue_name:, connection_string:)
        @queue_name = queue_name
        @http_client = HttpClient.new(connection_string: connection_string)
      end

      def peek_lock_message(timeout: DEFAULT_TIMEOUT)
        response = http_client.make_request(method: :post, path: "/#{queue_name}/messages/head", query: { timeout: timeout })
        handle_message_response(response)
      end

      def delete_message(message)
        http_client.make_request_to_uri(method: :delete, uri: URI(message.location))
      end

      def read_and_delete_message(timeout: DEFAULT_TIMEOUT)
        response = http_client.make_request(method: :delete, path: "/#{queue_name}/messages/head", query: { timeout: timeout })
        handle_message_response(response)
      end

      def send_message(message)
        http_client.make_request(method: :post, path: "/#{queue_name}/messages", body: message, headers: { "Content-Type" => "text/plain" })
      end

      def unlock_message(message)
        http_client.make_request_to_uri(method: :put, uri: URI(message.location))
      end

      private

      attr_accessor :queue_name, :http_client

      def handle_message_response(response)
        # If there are still no messages in the queue after `timeout` seconds we get a 204
        if response.status == 204
          nil
        else
          Message.from_response(response)
        end
      end
    end
  end
end
