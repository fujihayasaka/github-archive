# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positions
      # ActiveRecord serialization coder for Positions objects.
      #
      # This class provides the interface required by ActiveRecord's `serialize` method
      # to handle encoding and decoding of Positions objects to/from JSON for database storage.
      # It implements the dump/load contract expected by ActiveRecord coders.
      #
      # Usage in ActiveRecord models:
      #   serialize :positioning, PullRequests::CommentPosition::Positions::Coder
      class Coder
        # Called by ActiveRecord when serializing a Positions object for database storage.
        # This method converts a Positions object to a JSON string that can be stored
        # in a database column (typically TEXT or JSON column type).
        #
        # The value parameter is untyped because ActiveRecord can pass various types:
        # - Positions objects that need serialization
        # - Already serialized hashes from user input
        # - nil values
        # - Other unexpected types that should be passed through
        sig { params(value: T.untyped).returns(T.nilable(String)) }
        def self.dump(value)
          return if value.nil?

          hash = case value
          when Positions
            Database.serialize(value)
          else
            value
          end

          ActiveSupport::JSON.dump(hash) if hash
        end

        # Called by ActiveRecord when deserializing a value from the database back
        # into a Positions object. This method takes the JSON string stored in the
        # database and converts it back to the appropriate Positions instance.
        #
        # The value parameter is untyped because it could be:
        # - JSON strings from the database
        # - Already parsed hashes
        # - nil values from NULL database columns
        # - Other unexpected types that the deserializer should handle gracefully
        sig { params(value: T.untyped).returns(T.nilable(Positions)) }
        def self.load(value) = Parser.parse_or_nil(value)
      end
    end
  end
end
