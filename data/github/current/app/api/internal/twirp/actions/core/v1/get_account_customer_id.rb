# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Resolves the billing CustomerID for a given (account_id, account_type) pair
      class GetAccountCustomerId
        ACCOUNT_TYPE_USER         = :ACCOUNT_TYPE_USER
        ACCOUNT_TYPE_ORGANIZATION = :ACCOUNT_TYPE_ORGANIZATION
        ACCOUNT_TYPE_ENTERPRISE   = :ACCOUNT_TYPE_ENTERPRISE

        VALID_ACCOUNT_TYPES = [
          ACCOUNT_TYPE_USER,
          ACCOUNT_TYPE_ORGANIZATION,
          ACCOUNT_TYPE_ENTERPRISE,
        ].freeze

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @account_id = request.account_id
          @account_type = request.account_type
        end

        def call
          if @account_id.zero?
            return Twirp::Error.invalid_argument("account_id is required", argument: "account_id")
          end

          unless VALID_ACCOUNT_TYPES.include?(@account_type)
            return Twirp::Error.invalid_argument(
              "account_type must be ACCOUNT_TYPE_USER, ACCOUNT_TYPE_ORGANIZATION, or ACCOUNT_TYPE_ENTERPRISE",
              argument: "account_type",
            )
          end

          entity = lookup_entity
          return Twirp::Error.not_found("account does not exist", argument: "account_id") unless entity

          billable_owner = case entity
          when Organization, Business
            Billing::EntityResolver.billing_owner(entity)
          when User
            entity
          end

          return Twirp::Error.not_found("billing owner does not exist", argument: "account_id") unless billable_owner

          customer = billable_owner.customer
          return Twirp::Error.not_found("customer does not exist", argument: "account_id") unless customer

          { customer_id: customer.id }
        end

        private

        def lookup_entity
          case @account_type
          when ACCOUNT_TYPE_USER
            user = User.find_by(id: @account_id)
            # Organization < User via STI. Reject org rows so ACCOUNT_TYPE_USER only matches real users.
            user&.user? ? user : nil
          when ACCOUNT_TYPE_ORGANIZATION
            Organization.find_by(id: @account_id)
          when ACCOUNT_TYPE_ENTERPRISE
            Business.find_by(id: @account_id)
          end
        end
      end
    end
  end
end
