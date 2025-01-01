# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesCopilotLicensingSettingsControllerHttpTest < GitHub::IntegrationTestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @business = create(:business, owners: [@owner], seats_plan_type: :full)
    create(:billing_sales_serve_plan_subscription, customer: @business.customer)

    @organization = create(:organization, business: @business, admins: [@owner])
  end

  context "#index" do
    if GitHub.billing_enabled?
      test "renders the Copilot Licensing sub menu page" do
        enable_feature_flag(:enterprise_copilot_licensing)
        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing/copilot"
        assert_response :ok
      end

      test "does not render if the feature flag is disabled" do
        disable_feature_flag(:enterprise_copilot_licensing)
        as @owner

        get "/enterprises/#{@business.slug}/enterprise_licensing/copilot"
        assert_response :not_found
      end
    end
  end
end
