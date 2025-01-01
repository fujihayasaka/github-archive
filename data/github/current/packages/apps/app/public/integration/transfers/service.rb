# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Service
      sig { params(integration: Integration, target: T.any(User, Organization, Business), requester: User, stafftools_initiated: T::Boolean).returns(Result) }
      def self.start!(integration:, target:, requester:, stafftools_initiated: false)
        Initiator.new(
          integration: integration,
          target: target,
          requester: requester,
          stafftools_initiated: stafftools_initiated
        ).start!
      end

      sig { params(integration: Integration, target: T.any(User, Organization, Business), stafftools_initiated: T::Boolean).returns(T::Boolean) }
      def self.can_transfer?(integration:, target:, stafftools_initiated: false)
        Validator.new(
          integration: integration,
          target: target,
          stafftools_initiated: stafftools_initiated
        ).valid?
      end

      sig { params(xfer: IntegrationTransfer, responder: User, entry_point: Symbol).returns(Result) }
      def self.finish!(xfer:, responder:, entry_point:)
        Accept.perform(transfer: xfer, responder:, entry_point:, stafftools_initiated: false)
      end

      sig { params(xfer: IntegrationTransfer, responder: User).returns(Result) }
      def self.cancel!(xfer:, responder:)
        Executor.new(xfer, responder).cancel!
      end

      sig { params(integration: Integration, target: T.any(User, Organization, Business), staff_user: User, entry_point: Symbol).returns(Result) }
      def self.stafftools_transfer_ownership(integration:, target:, staff_user:, entry_point:)
        TransferOwnership.perform(integration:, target:, requester: staff_user, responder: staff_user, entry_point:, stafftools_initiated: true)
      end
    end
  end
end
