# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Api::ListProductUsageMethodsTest < GitHub::TestCase
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
      mock_list_product_usage_response(product: "codespaces", unit_of_measure: "Hours", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      refute result.has_error?
    end

    test "returns true when error occurs" do
      mock_list_product_usage_response_error
      result = @client_wrapper.codespaces_monthly_usage
      assert result.has_error?
    end
  end

  context "#copilot_usage" do
    test "returns copilot usage" do
      mock_list_product_usage_response(product: "copilot", sku_name: "copilot_for_business", unit_of_measure: "User Month", quantity: 1_000.0, subunits: 1_000_000)
      result = @client_wrapper.copilot_monthly_usage
      assert_equal 1_000.0, result.meuse_product_usage
      assert_equal 1_000_000.0, result.meuse_product_cost
    end
  end

  context "#ghec_usage" do
    test "returns ghec usage" do
      mock_list_product_usage_response(product: "ghec", sku_name: "seats", unit_of_measure: "User Month", quantity: 1_000.0, subunits: 1_000_000)
      result = @client_wrapper.ghec_monthly_usage
      assert_equal 1_000.0, result.meuse_product_usage
      assert_equal 1_000_000.0, result.meuse_product_cost
    end
  end

  context "#compute_usage" do
    test "returns compute usage" do
      mock_list_product_usage_with_compute_and_storage_response(compute_sku: "compute_d2", compute_quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      compute_usage = result.compute_usage
      assert_equal 1, compute_usage.size
      assert_equal "compute_d2", compute_usage[0][:product_sku][:name]
      assert_equal 1_000.0, compute_usage[0][:usage][:quantity]
    end
  end

  context "#storage_usage" do
    test "returns storage usage" do
      mock_list_product_usage_with_compute_and_storage_response(storage_sku: "storage", storage_quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      storage_usage = result.storage_usage
      assert_equal 1, storage_usage.size
      assert_equal "storage", storage_usage[0][:product_sku][:name]
      assert_equal 1_000.0, storage_usage[0][:usage][:quantity]
    end
  end

  context "#compute_usage_by_sku" do
    test "returns correct compute usage" do
      mock_list_product_usage_with_compute_and_storage_response(compute_sku: "compute_d2", compute_quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      compute_usage = result.compute_usage_by_sku("compute_d2")
      assert_equal "compute_d2", compute_usage[:product_sku][:name]
      assert_equal 1_000.0, compute_usage[:usage][:quantity]
    end

    test "returns nil when compute usage is not found" do
      mock_list_product_usage_with_compute_and_storage_response(compute_sku: "compute_d2", compute_quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      assert_nil result.compute_usage_by_sku("compute_dx")
    end
  end

  context "#compute_total_usage_by_sku" do
    test "returns total compute usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 500.0, result.compute_total_usage_by_sku("compute_d2")
    end

    test "returns 0 when compute usage is not found" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_total_usage_by_sku("compute_dx")
    end
  end

  context "#compute_effective_usage_by_sku" do
    test "returns effective compute usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 500.0, result.compute_effective_usage_by_sku("compute_d2")
    end

    test "returns 0 when compute usage is not found" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_effective_usage_by_sku("compute_dx")
    end
  end

  context "#compute_total_cost_by_sku" do
    test "returns total compute cost only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_subunits: 1_000,
        storage_sku: "storage",
        storage_subunits: 500
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 1_000, result.compute_total_cost_by_sku("compute_d2")
    end

    test "returns 0 when compute cost is not found" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_subunits: 1_000,
        storage_sku: "storage",
        storage_subunits: 500
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_total_cost_by_sku("compute_dx")
    end
  end

  context "#compute_total_usage" do
    test "returns total compute usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 500.0, result.compute_total_usage
    end

    test "returns 0 when compute usage is not found" do
      mock_list_product_usage_response(sku_name: "storage", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_total_usage
    end
  end

  context "#compute_effective_usage" do
    test "returns effective compute usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 500.0, result.compute_effective_usage
    end

    test "returns 0 when compute usage is not found" do
      mock_list_product_usage_response(sku_name: "storage", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_effective_usage
    end
  end

  context "#storage_total_usage" do
    test "returns total storage usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 300.0, result.storage_total_usage
    end

    test "returns 0 when storage usage is not found" do
      mock_list_product_usage_response(sku_name: "compute_d2", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.storage_total_usage
    end
  end

  context "#storage_effective_usage" do
    test "returns effective storage usage only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_quantity: 500.0,
        storage_sku: "storage",
        storage_quantity: 300.0
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 300.0, result.storage_effective_usage
    end

    test "returns 0 when storage usage is not found" do
      mock_list_product_usage_response(sku_name: "compute_d2", quantity: 1_000.0)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.storage_effective_usage
    end
  end

  context "#compute_total_cost_in_subunits" do
    test "returns total compute cost only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_subunits: 1_000,
        storage_sku: "storage",
        storage_subunits: 500
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 1_000, result.compute_total_cost_in_subunits
    end

    test "returns 0 when compute cost is not found" do
      mock_list_product_usage_response(sku_name: "storage", subunits: 1_000)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.compute_total_cost_in_subunits
    end
  end

  context "#storage_total_cost_in_subunits" do
    test "returns total storage cost only" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_subunits: 1_000,
        storage_sku: "storage",
        storage_subunits: 500
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 500, result.storage_total_cost_in_subunits
    end

    test "returns 0 when storage cost is not found" do
      mock_list_product_usage_response(sku_name: "compute_d2", subunits: 1_000)
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 0, result.storage_total_cost_in_subunits
    end
  end

  context "#total_cost_in_subunits" do
    test "returns total cost regardless of sku name" do
      mock_list_product_usage_with_compute_and_storage_response(
        compute_sku: "compute_d2",
        compute_subunits: 1_000,
        storage_sku: "storage",
        storage_subunits: 500
      )
      result = @client_wrapper.codespaces_monthly_usage
      assert_equal 1_500, result.total_cost_in_subunits
    end
  end
end
