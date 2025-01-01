# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecurityCancelSubscriptionsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus


  fixtures do
    @owner = create(:user)
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
  end

  context "GET /enterprises/:slug/settings/advanced_security/cancel_subscriptions" do
    test "cancels existing subscription" do
      as @owner
      get "/enterprises/#{@business.to_param}/settings/advanced_security/cancel_subscriptions", xhr: :true
      assert_response 200
      assert_select "h2", text: "Cancel GitHub Advanced Security"
    end
  end if GitHub.billing_enabled?
end
