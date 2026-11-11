# rubocop:disable Lint/GenericRescue
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
          @fetch_error = false
        end

        sig { returns(T.nilable(T.any(User, Business, Organization))) }
        memoize def billable_owner
          customer = Customer.find_by(id: @customer_id)
          customer&.billable_owner
        end

        sig { returns(String) }
        def description
          data = cost_center_data
          return "" if @fetch_error

          return "" if data.nil?

          T.must(data).dig(:description) || ""
        end

        sig { returns(String) }
        def name
          data = cost_center_data
          return "" if @fetch_error

          return "Deleted" if data.nil?

          T.must(data).dig(:name) || ""
        end

        private

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        memoize def cost_center_data
          @fetch_error = false

          begin
            cost_center_response = billing_platform_client.get_cost_center(cost_center_key: {
              customerId: @customer_id,
              uuid: @uuid
            })

          rescue => e
            Failbot.report(e, customer_id: @customer_id, uuid: @uuid)
            @fetch_error = true
            return nil
          end

          if cost_center_response.is_a?(Billing::Platform::Api::Error)
            Failbot.report(cost_center_response, customer_id: @customer_id, uuid: @uuid)
            @fetch_error = true
            return nil
          end

          cost_center_response[:costCenter]
        end

        def billing_platform_client
          Billing::Platform::Api::Client.new
        end
      end
    end
  end
end
