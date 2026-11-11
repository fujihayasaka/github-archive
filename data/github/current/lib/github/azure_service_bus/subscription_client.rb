# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class SubscriptionClient
      DEFAULT_TIMEOUT = T.let(60, Integer)

      sig do
        params(
          topic_name: String,
          subscription_name: String,
          connection_string: T.nilable(String),
          namespace: T.nilable(String),
          token_provider: T.nilable(GitHub::Azure::ApplicationTokenProvider)
        ).void
      end
      def initialize(topic_name:, subscription_name:, connection_string: nil, namespace: nil, token_provider: nil)
        @topic_name = T.let(topic_name, String)
        @subscription_name = T.let(subscription_name, String)

        if connection_string
          @http_client = T.let(SasHttpClient.new(connection_string: connection_string), IHttpClient)
        elsif namespace && token_provider
          @http_client = T.let(AadHttpClient.new(namespace: namespace, token_provider: token_provider), IHttpClient)
        else
          raise ArgumentError, "Must provide either connection_string for SAS auth or namespace + token_provider for AAD auth"
        end
      end

      sig { params(timeout: Integer).returns(T.nilable(Message)) }
      def peek_lock_message(timeout: DEFAULT_TIMEOUT)
        response = http_client.make_request(
          method: :post,
          path: "/#{topic_name}/subscriptions/#{subscription_name}/messages/head",
          query: { timeout: timeout }
        )
        handle_message_response(response)
      end

      sig { params(message: Message).returns(Faraday::Response) }
      def delete_message(message)
        location = message.location
        raise ArgumentError, "Message location is required for delete operation" if location.nil?
        http_client.make_request_to_uri(method: :delete, uri: URI(location))
      end

      sig { params(timeout: Integer).returns(T.nilable(Message)) }
      def read_and_delete_message(timeout: DEFAULT_TIMEOUT)
        response = http_client.make_request(
          method: :delete,
          path: "/#{topic_name}/subscriptions/#{subscription_name}/messages/head",
          query: { timeout: timeout }
        )
        handle_message_response(response)
      end

      sig { params(message: String).returns(Faraday::Response) }
      def send_message(message)
        http_client.make_request(method: :post, path: "/#{topic_name}/messages", body: message, headers: { "Content-Type" => "text/plain" })
      end

      sig { params(message: Message).returns(Faraday::Response) }
      def unlock_message(message)
        location = message.location
        raise ArgumentError, "Message location is required for unlock operation" if location.nil?
        http_client.make_request_to_uri(method: :put, uri: URI(location))
      end

      private

      sig { returns(String) }
      attr_accessor :topic_name, :subscription_name
      sig { returns(IHttpClient) }
      attr_accessor :http_client

      sig { params(response: Faraday::Response).returns(T.nilable(Message)) }
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
