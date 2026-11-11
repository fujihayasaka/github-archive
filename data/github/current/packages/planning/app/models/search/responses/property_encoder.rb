# typed: strict
# frozen_string_literal: true

# Class that manages encoding and decoding arbitrary data into opaque strings
# for use in REST and GraphQL API responses.
# This is used to encode and decode cursors for pagination,
# as well as slice and group identifiers.
module Search
  module Responses
    class PropertyEncoder
      sig { params(property: T.untyped).returns(T.nilable(String)) }
      def self.encode(property)
        return unless property
        Platform::ConnectionWrappers::CursorGenerator.generate_cursor(property, version: :v2)
      end

      sig { params(property: T.nilable(String)).returns(T.nilable(T.anything)) }
      def self.resolve(property)
        return unless property
        Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(property)
      end
    end
  end
end
