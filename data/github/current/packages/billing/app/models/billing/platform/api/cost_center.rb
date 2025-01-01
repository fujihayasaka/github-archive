# typed: true
# frozen_string_literal: true

# Class to represent cost center data from the billing platform
module Billing
  module Platform
    module Api
      class CostCenter
        include GitHub::Memoizer

        sig do
          params(
            customer_id: String,
            uuid: String
          ).void
        end
        def initialize(customer_id:, uuid:)
          @customer_id = customer_id
          @uuid = uuid
        end

        sig { returns(T.nilable(T.any(User, Business, Organization))) }
        memoize def billable_owner
          customer = Customer.find_by(id: @customer_id)
          customer&.billable_owner
        end

        sig { returns(String) }
        memoize def name
          begin
            cost_center_response = billing_platform_client.get_cost_center(cost_center_key: {
              customerId: @customer_id,
              uuid: @uuid
            })
          rescue => e # rubocop:todo Lint/GenericRescue
            return ""
          end

          if cost_center_response.is_a?(Billing::Platform::Api::Error)
            return ""
          end

          cost_center_response[:costCenter][:name]
        end

        private

        def billing_platform_client
          Billing::Platform::Api::Client.new
        end
      end
    end
  end
end
