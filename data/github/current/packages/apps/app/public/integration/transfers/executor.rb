# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Executor

      sig { returns(IntegrationTransfer) }
      attr_reader :transfer

      sig { returns(User) }
      attr_reader :responder

      sig { params(transfer: IntegrationTransfer, responder: User).void }
      def initialize(transfer, responder)
        @transfer = transfer
        @responder = responder
      end

      sig { returns(Result) }
      def cancel!
        return Result.failure("Cannot be cancelled by user") unless transfer.cancelable_by?(responder)

        integration = transfer.integration

        if transfer.destroy
          Result.success(T.must(integration), "Transfer cancelled")
        else
          Result.failure("Transfer could not be cancelled")
        end
      rescue ActiveRecord::RecordInvalid => e
        Result.failure(e.message)
      end
    end
  end
end
