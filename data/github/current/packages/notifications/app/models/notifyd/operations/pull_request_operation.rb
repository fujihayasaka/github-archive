# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over PullRequests
    class PullRequestOperation < T::Enum
      extend T::Sig

      enums do
        Unknown = new("unknown")
        Create = new("create")
        Update = new("update")
        Assigned = new("assigned")
        ReviewRequested = new("review_requested")
      end

      sig { params(operation: T.nilable(String)).returns(PullRequestOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
