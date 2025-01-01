# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessUserAccounts::SidebarCostCenterComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @owner     = create(:user)
    @member    = create(:user, login: "org-member")
    @org       = create(:organization)
    @business  = create(:business, owners: [@owner], organizations: [@org])
  end

  def setup
    @org.add_member(@member)
  end

  def component
    @component ||= BusinessUserAccounts::SidebarCostCenterComponent.new(
      business: @business,
      user: @member
    )
  end

  test "show cost center when copilot billing platform enabled" do
    @business.customer.create_billing_platform_enabled_product(copilot: true)
    assert_predicate component, :render?
  end

  test "show cost center when ghec billing platform enabled" do
    @business.customer.create_billing_platform_enabled_product(ghec: true)
    assert_predicate component, :render?
  end

  test "dont show cost center when ghec and copilot billing platform disabled" do
    @business.customer.create_billing_platform_enabled_product(ghec: false , copilot: false)
    refute_predicate component, :render?
  end

  test "cost center returns name from billing platform" do
    component.billing_platform_client.stub(:find_cost_center_for, { costCenterKey: { uuid: SecureRandom.uuid } }) do
      component.billing_platform_client.stub(:get_cost_center, { costCenter: { name: "Test Cost Center" } }) do
        assert_equal component.cost_center, "Test Cost Center"
      end
    end
  end

  test "cost center returns nil when no cost center found" do
    component.billing_platform_client.stub(:find_cost_center_for, { costCenterKey: nil }) do
      assert_nil component.cost_center
    end
  end

  test "cost center returns unavailable when billing platform errs" do
    component.billing_platform_client.stub(:find_cost_center_for, Billing::Platform::Api::Error.new("Test error")) do
      assert_equal component.cost_center, "Unavailable"
    end
  end
end unless GitHub.single_business_environment?
