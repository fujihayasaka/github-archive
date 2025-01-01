# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over SecurityCampaignUser
    class SecurityCampaignUserOperation < T::Enum

      enums do
        Unknown = new("unknown")
        Create = new("create")
        Overdue = new("overdue")
      end

      sig { params(operation: T.nilable(String)).returns(SecurityCampaignUserOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
