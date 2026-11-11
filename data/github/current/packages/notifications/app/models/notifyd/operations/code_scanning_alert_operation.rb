# typed: true
# frozen_string_literal: true

module Notifyd
  module Operations
    # Supported operations over CodeScanningAlerts
    class CodeScanningAlertOperation < T::Enum

      enums do
        Unknown = new("unknown")
        Assigned = new("assigned")
        Dismissed = new("dismissed")
      end

      sig { params(operation: T.nilable(String)).returns(CodeScanningAlertOperation) }
      def self.try_deserialize_or_unknown(operation)
        try_deserialize(operation) || Unknown
      end
    end
  end
end
