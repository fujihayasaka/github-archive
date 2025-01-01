# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over IssueComments
    class IssueCommentOperation < T::Enum
      extend T::Sig

      enums do
        Unknown = new("unknown")
        Create = new("create")
        Update = new("update")
      end

      sig { params(operation: T.nilable(String)).returns(IssueCommentOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
