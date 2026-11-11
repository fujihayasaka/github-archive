# typed: true
# frozen_string_literal: true

require "monolith-twirp-billing-customers"

module Api::Internal::Twirp::Billing
  module Customers
    module V1
      class CustomerAPIHandler < Api::Internal::Twirp::Handler
        include Billing::CopilotLicenseSnapshot

        allow_access_for :client, allowed_clients: ["billing"]
        handles_service MonolithTwirp::Billing::Customers::V1::CustomerAPIService

        def trigger_copilot_license_snapshot(req, env)
          return Twirp::Error.invalid_argument("customer_id is required") if req.customer_id.blank? || req.customer_id.zero?

          customer = Customer.find_by(id: req.customer_id)
          return Twirp::Error.not_found("Customer #{req.customer_id} not found") unless customer

          billable_owner = customer.billable_owner
          return Twirp::Error.not_found("Billable owner for Customer #{req.customer_id} not found") unless billable_owner

          unless billable_owner.is_a?(::Business) || billable_owner.is_a?(::Organization)
            return Twirp::Error.invalid_argument("Billable owner for Customer #{req.customer_id} must be a Business or Organization")
          end

          owner = T.cast(billable_owner, T.any(::Business, ::Organization))
          result = refresh_copilot_license_snapshot(owner: owner, customer_id: req.customer_id, async: true)

          return Twirp::Error.internal(result.error_message) if result.error?

          MonolithTwirp::Billing::Customers::V1::TriggerCopilotLicenseSnapshotResponse.new
        end
      end
    end
  end
end
