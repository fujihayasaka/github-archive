# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::ClientTest < GitHub::TestCase
  include Billing::Platform::Api::Utils

  setup do
    @client = Billing::Platform::Api::Client.new
  end

  def billing_platform_client_response(data: {}, error: nil)
    Twirp::ClientResp.new(data: data, error: error)
  end

  context "#admin_trigger_invoice_generation" do
    test "performs a trigger invoice generation call" do
      BillingPlatform::Client.any_instance
        .expects(:admin_trigger_invoice_generation)
        .with(customerId: "1", month: 1, year: 2020)
        .returns(billing_platform_client_response(data: { success: true }))

      response = @client.admin_trigger_invoice_generation(customer_id: 1, month: 1, year: 2020)

      assert_equal true, response[:success]
    end
  end

  context "#get_budget" do
    test "returns a budget" do
      get_budget_response =
      {
        budget: {
          key: {
            customerId: "1",
            targetType: REPOSITORY_TARGET,
            targetId: "471549",
            pricingTargetType: 1,
            pricingTargetId: 1
          },
          targetAmount: 99.9,
          budgetLimitType: :PreventFurtherUsage
        },
        budgetState: {
          isFullyFunded: false,
          currentAmount: 0.0,
          targetAmount: 99.9,
          quantity: 0.0
        }
      }

      budget_key = {
        customerId: "1",
        targetType: REPOSITORY_TARGET,
        targetId: "471549",
        pricingTargetType: 1,
        pricingTargetId: 1
      }

      ::Billing::Platform::Api::Client.any_instance
      .stubs(:get_budget)
      .returns(get_budget_response)

      response = @client.get_budget(key: budget_key)

      assert response.is_a?(Hash)
    end
  end

  context "#get_budget_by_uuid" do
    test "returns a budget" do
      get_budget_by_uuid_response =
      {
        budget: {
          key: {
            customerId: "1",
            targetType: REPOSITORY_TARGET,
            targetId: "471549",
            pricingTargetType: 1,
            pricingTargetId: 1
          },
          targetAmount: 99.9,
          budgetLimitType: :PreventFurtherUsage
        },
        budgetState: {
          isFullyFunded: false,
          currentAmount: 0.0,
          targetAmount: 99.9,
          quantity: 0.0
        }
      }

      ::Billing::Platform::Api::Client.any_instance
      .stubs(:get_budget_by_uuid)
      .returns(get_budget_by_uuid_response)

      response = @client.get_budget_by_uuid(customer_id: "1", uuid: "1")

      assert response.is_a?(Hash)
    end
  end

  context "#delete_budget" do
    test "deletes a budget" do
      ::Billing::Platform::Api::Client.any_instance
      .stubs(:delete_budget)
      .returns({})

      response = @client.delete_budget(customer_id: "1", uuid: "1")

      assert response.is_a?(Hash)
    end
  end
end
