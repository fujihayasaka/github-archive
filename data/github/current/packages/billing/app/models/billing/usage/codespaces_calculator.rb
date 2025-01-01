# typed: true
# frozen_string_literal: true

class Billing::Usage::CodespacesCalculator
  def initialize(billable_owner:, owner: nil)
    @billable_owner = billable_owner
    @owner = owner
    @client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: billable_owner, owner: owner)
  end

  def cost
    usage_from_api[:usage_quotes].sum { |usage| usage[:total_historical_usage][:estimated_cost][:subunits] }
  end

  private

  attr_reader :billable_owner, :client_wrapper

  def usage_from_api
    @_usage_from_api ||= query_billing_api
  end

  def query_billing_api
    timestamp = client_wrapper.billable_owner.current_metered_billing_cycle_starts_at
    metered_cycle_starts_at = Google::Protobuf::Timestamp.new(seconds: timestamp.to_i)
    proposed_usage = [
      {
        # Use any SKU since the Billing API returns the estimated cost for the product
        product_name: :codespaces,
        product_sku_name: :compute_d2,
        proposed_quantity: 0,
        entitlement_quantity: 0
      },
      {
        product_name: :codespaces,
        product_sku_name: :storage,
        proposed_quantity: 0,
        entitlement_quantity: 0,
      },
    ]
    response = client_wrapper.calculate_usage_quotes(proposed_usage, metered_cycle_starts_at)

    raise response if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

    response
  end
end
