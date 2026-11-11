# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over Discussions
    class DiscussionOperation < T::Enum
      enums do
        Unknown = new("unknown")
        Create = new("create")
        Update = new("update")
      end

      sig { params(operation: T.nilable(String)).returns(DiscussionOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
