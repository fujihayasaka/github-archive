# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positions
      module Database
        # Serializes position objects for database storage, preserving all fields including
        # internal commit OIDs. This full serialization ensures that all positioning data
        # is maintained in the database for complete reconstruction during deserialization.
        sig { params(value: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
        def self.serialize(value)
          case value
          when Positions then value.serialize
          else value
          end
        end

        # Deserializes position data from database storage back into typed Position objects.
        # Uses the parser's parse_or_nil method to safely handle potentially corrupted or
        # invalid data, returning nil if the stored data cannot be successfully parsed.
        sig { params(value: T.untyped).returns(T.nilable(Positions)) }
        def self.deserialize(value) = Parser.parse_or_nil(value)
      end
    end
  end
end
