# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecuritySuggestionFlowOrganizationsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
  end

  context "UPDATE /enterprises/:slug/settings/advanced_security/suggestion_flow/organizations" do
    test "404 if FF is not enabled" do
      GitHub.flipper[:ghas_self_serve_recommendation].disable(@business)
      org1 = create(:organization, business: @business)
      org2 = create(:organization, business: @business)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/organizations",
        params: { selected_org_ids: [org1.id, org2.id] }, xhr: true

      assert_response :not_found
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get("organizations:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "stores selected organization ids in the kv store" do
      GitHub.flipper[:ghas_self_serve_recommendation].enable(@business)
      org1 = create(:organization, business: @business)
      org2 = create(:organization, business: @business)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/organizations",
        params: { selected_org_ids: [org1.id, org2.id] }, xhr: true

      assert_response :success
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_equal [org1.id, org2.id].join(","), GitHub.kv.get("organizations:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "does not update selected organizations if not authorized" do
      GitHub.flipper[:ghas_self_serve_recommendation].enable(@business)
      org = create(:organization, business: @business)
      user = create(:user)
      org.add_member(user)

      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/organizations",
        params: { selected_org_ids: [org.id] }, xhr: true

      assert_response :not_found
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get("organizations:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end if GitHub.billing_enabled?
end
