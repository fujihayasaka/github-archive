# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::AzureSubscriptionCheckComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "Success rendered when paying with azure paper" do
    business = create(:business)
    create(:enterprise_agreement, business: business)

    business.customer.stub(:invalid_azure_subscription_detected?, false) do
      render_inline(Licensing::AzureSubscriptionCheckComponent.new(business: business), allowed_queries: 2)
      assert_test_selector("azure-subscription-check", text: "Valid azure subscription setup")
    end
  end

  test "Error rendered with invalid azure subscription" do
    business = create(:business)
    create(:enterprise_agreement, business: business)

    business.customer.stub(:invalid_azure_subscription_detected?, true) do
      render_inline(Licensing::AzureSubscriptionCheckComponent.new(business: business), allowed_queries: 2)
      assert_test_selector("azure-subscription-check", text: "Azure subscription must be setup")
    end
  end

  test "Not rendered when not paying with azure paper" do
    business = create(:business)

    render_inline(Licensing::AzureSubscriptionCheckComponent.new(business: business), allowed_queries: 1)

    refute_test_selector("azure-subscription-check", text: "Azure subscription must be setup")
  end
end
