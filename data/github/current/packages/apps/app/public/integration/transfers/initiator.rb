# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Initiator

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(T.any(User, Organization, Business)) }
      attr_reader :target

      sig { returns(User) }
      attr_reader :requester

      sig { returns(T::Boolean) }
      attr_reader :stafftools_initiated

      sig { params(integration: Integration, target: T.any(User, Organization, Business), requester: User, stafftools_initiated: T::Boolean).void }
      def initialize(integration:, target:, requester:,  stafftools_initiated: false)
        @integration = integration
        @target = target
        @requester = requester
        @stafftools_initiated = stafftools_initiated
      end

      # Public: Request an ownership change for integration. Sends an email to the
      # target's owners asking them to respond to this transfer request.
      #
      # integration     - An Integration
      # target          - The User, Organization, or Business who will own the app after transfer
      # requester       - The User responsible for this request
      #
      # Returns a new Result instance.
      # Raises ActiveRecord::RecordInvalid for bad integration/target/requester combos.
      sig { returns(Result) }
      def start!
        return Result.failure("Invalid transfer") unless transfer_valid?

        xfer = IntegrationTransfer.create! do |x|
          x.integration = integration
          x.requester   = requester
          x.target      = target
        end

        unless target.adminable_by?(requester)
          AccountMailer.integration_transfer_request(xfer).deliver_later
        end

        Result.success(integration, "Transfer started")
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
