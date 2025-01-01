# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over Issues
    class IssueOperation < T::Enum
      extend T::Sig

      enums do
        Unknown = new("unknown")
        Create = new("create")
        Update = new("update")
        Labeled = new("labeled")
        Unlabeled = new("unlabeled")
        Assigned = new("assigned")
        Closed = new("closed")
        Reopened = new("reopened")
        ConvertedToDiscussion = new("converted_to_discussion")
      end

      sig { params(operation: T.nilable(String)).returns(IssueOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
