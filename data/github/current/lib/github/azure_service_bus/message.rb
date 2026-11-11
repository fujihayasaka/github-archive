# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class Message
      sig { params(response: T.untyped).returns(Message) }
      def self.from_response(response)
        new(
          body: response.body,
          location: response.headers["location"]
        )
      end

      sig { returns(String) }
      attr_reader :body

      sig { returns(T.nilable(String)) }
      attr_reader :location

      sig { params(body: String, location: T.nilable(String)).void }
      def initialize(body:, location:)
        @body = T.let(body, String)
        @location = T.let(location, T.nilable(String))
      end
    end
  end
end
