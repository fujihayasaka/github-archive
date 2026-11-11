# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Accept

      sig { returns(IntegrationTransfer) }
      attr_reader :transfer

      sig { returns(User) }
      attr_reader :responder

      sig { returns(Symbol) }
      attr_reader :entry_point

      sig { returns(T::Boolean) }
      attr_reader :stafftools_initiated

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :target

      sig do
        params(
          transfer: IntegrationTransfer,
          responder: User,
          entry_point: Symbol,
          stafftools_initiated: T::Boolean
        ).returns(Result)
      end
      def self.perform(transfer:, responder:, entry_point:, stafftools_initiated: false)
        new(
          transfer: transfer,
          responder: responder,
          entry_point: entry_point,
          stafftools_initiated: stafftools_initiated
        ).perform
      end

      sig do
        params(
          transfer: IntegrationTransfer,
          responder: User,
          entry_point: Symbol,
          stafftools_initiated: T::Boolean
        ).void
      end
      def initialize(transfer:, responder:, entry_point:, stafftools_initiated:)
        @transfer = transfer
        @responder = responder
        @stafftools_initiated = stafftools_initiated
        @entry_point = entry_point
        @integration = T.let(T.must(transfer.integration), Integration)
        @target = T.let(transfer.target, T.any(User, Organization, Business))
      end

      sig { returns(Result) }
      def perform
        return Result.failure("Invalid transfer") unless transfer_valid?

        transfer.finish(responder, entry_point: entry_point)
        Result.success(T.must(transfer.integration), "Transfer completed")
      rescue ActiveRecord::RecordInvalid => e
        Result.failure(e.message)
      end

      private

      sig { returns(T::Boolean) }
      def transfer_valid?
        Validator.new(
          integration: integration,
          target: target,
          stafftools_initiated: stafftools_initiated
        ).valid?
      end
    end
  end
end
