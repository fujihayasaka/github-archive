# typed: strict
# frozen_string_literal: true

module SpokesAPI
  module Types
    class DiffPositionState < T::Enum
      enums do
        Success = new(:STATE_CODE_SUCCESS)
        RemovedPath = new(:STATE_CODE_REMOVED_PATH)
        InvalidPath = new(:STATE_CODE_INVALID_PATH)
        ContentTooLarge = new(:STATE_CODE_CONTENT_TOO_LARGE)
        Unknown = new(:unknown)
      end

      # Safely deserialize the API value, falling back to `Unknown`. This is safe to future changes
      # as uncaught values will default to unknown rather than throwing.
      sig { params(value: T.untyped).returns(DiffPositionState) }
      def self.safe_deserialize(value)
        deserialize(value)
      rescue KeyError
        Unknown
      end
    end
  end
end
