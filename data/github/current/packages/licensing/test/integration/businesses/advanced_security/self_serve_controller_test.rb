# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecuritySelfServeControllerHttpTest < GitHub::IntegrationTestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
  end

  context "GET /show" do
    test "returns 404 if not advanced security is not enabled" do
      Business.any_instance.stubs(:eligible_for_self_serve_advanced_security?).returns(false)
      as @owner
      get "/enterprises/#{@business.to_param}/settings/billing/ghas/seat_price", params: { seats: "14" }, xhr: true
      assert_response :not_found
    end
  end if GitHub.billing_enabled?
end
