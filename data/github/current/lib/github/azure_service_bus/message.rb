# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class Message
      def self.from_response(response)
        new(
          body: response.body,
          location: response.headers["location"]
        )
      end

      attr_reader :body, :location

      def initialize(body:, location:)
        @body = body
        @location = location
      end
    end
  end
end
