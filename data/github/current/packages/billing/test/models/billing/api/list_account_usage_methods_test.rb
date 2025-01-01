# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Api::ListAccountUsageMethodsTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  fixtures do
    @business = create(:business, :with_azure_subscription)
    @organization = create(:organization, business: @business)
    @user = create(:user)
  end

  setup do
    @client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: @business, owner: @organization)
  end

  context "#has_error?" do
    test "returns false when result is valid" do
      mock_list_account_usage_response(product: "codespaces", unit_of_measure: "Hours", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage_by_owner
      refute result.has_error?
    end

    test "returns true when error occurs" do
      mock_list_account_usage_response_error
      result = @client_wrapper.codespaces_monthly_usage_by_owner
      assert result.has_error?
    end
  end

  context "#total_codespaces_usage_by_owner" do
    test "returns total codespaces usage by owner" do
      mock_list_account_usage_with_compute_and_storage_response(
        account_id: @organization.id,
        product: "codespaces",
        compute_quantity: 500.0,
        compute_subunits: 100,
        storage_quantity: 300.0,
        storage_subunits: 200,
      )

      response = @client_wrapper.codespaces_monthly_usage_by_owner
      result = response.total_codespaces_usage_by_owner.first

      assert_equal(result[:owner_id], @organization.id)
      assert_equal(result[:owner_type], :OWNER_TYPE_USER)
      assert_equal(result[:compute_effective_quantity], 500.0)
      assert_equal(result[:storage_effective_quantity], 300.0)
      assert_equal(result[:cost_in_subunits], 300)
    end
  end

  context "#total_copilot_usage_by_owner" do
    test "returns total copilot usage by owner" do
      skus = [
        ProductSku.new(name: "copilot_for_business", quantity: 2, subunits: 100),
        ProductSku.new(name: "copilot_enterprise", quantity: 3, subunits: 200),
      ]
      mock_list_account_usage_with_copilot_skus_response(
        account_id: @organization.id,
        product: "copilot",
        skus: skus,
      )

      response = @client_wrapper.copilot_monthly_usage_by_owner
      result = response.total_copilot_usage_by_owner.first

      assert_equal(result[:owner_id], @organization.id)
      assert_equal(result[:owner_type], :OWNER_TYPE_USER)
      assert_equal(result[:effective_quantity], 5.0)
      assert_equal(result[:cost_in_subunits], 300)
    end
  end
end
