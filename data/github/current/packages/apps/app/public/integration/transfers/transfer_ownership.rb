# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class TransferOwnership

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :target

      sig { returns(User) }
      attr_reader :requester

      sig { returns(User) }
      attr_reader :responder

      sig { returns(T::Boolean) }
      attr_reader :stafftools_initiated

      sig { returns(Symbol) }
      attr_reader :entry_point

      sig { params(integration: Integration, target: T.any(User, Organization, Business), requester: User, responder: User, entry_point: Symbol, stafftools_initiated: T::Boolean).returns(Result) }
      def self.perform(integration:, target:, requester:, responder:, entry_point:, stafftools_initiated: false)
        new(integration:, target:, requester:, responder:, entry_point:, stafftools_initiated:).perform
      end

      sig { params(integration: Integration, target: T.any(User, Organization, Business), requester: User, responder: User, entry_point: Symbol, stafftools_initiated: T::Boolean).void }
      def initialize(integration:, target:, requester:, responder:, entry_point:, stafftools_initiated:)
        @integration = integration
        @target = target
        @requester = requester
        @responder = responder
        @stafftools_initiated = stafftools_initiated
        @entry_point = entry_point
      end

      sig { returns(Result) }
      def perform
        return Result.failure("Invalid transfer") unless transfer_valid?

        integration.transfer_ownership_to(target, requester:, responder:, entry_point:, stafftools_initiated:)

        Result.success(integration, "Transfer completed")
      rescue ActiveRecord::RecordInvalid => e
        Result.failure(e.message)
      end

      private

      sig { returns(T::Boolean) }
      def transfer_valid?
        Validator.new(integration:, target:, stafftools_initiated:).valid?
      end
    end
  end
end
