# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Formats
    module V3
      GRAPHQL_PREFIX = "g"
      VERSION = "v3"
      CHANNEL_PREFIX = "#{GRAPHQL_PREFIX}:#{VERSION}"

      def self.generate_channel_name(topic:, subscription_arguments:)
        "#{CHANNEL_PREFIX}:#{topic}:#{Codec.encode(subscription_arguments)}"
      end
    end
  end
end
