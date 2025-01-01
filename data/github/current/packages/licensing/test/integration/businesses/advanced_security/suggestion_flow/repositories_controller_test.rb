# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesAdvancedSecuritySuggestionFlowRepositoriesControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus

  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @business = create(:business, :with_self_serve_payment, owners: [@owner])
  end

  context "UPDATE /enterprises/:slug/settings/advanced_security/suggestion_flow/repositories" do
    test "stores selected organization ids in the kv store" do
      enable_feature_flag(:ghas_self_serve_recommendation, @business)
      org = create(:organization, business: @business)
      Billing::Kv.store.set("organizations:#{@business.id}:ghas_suggestion_flow", "#{org.id}")
      repo = create(:repository, owner: org)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response :success
      assert_equal [repo.id].join(","), Billing::Kv.store.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
    end

    test "404 if FF is not enabled" do
      disable_feature_flag(:ghas_self_serve_recommendation, @business)
      org = create(:organization, business: @business)
      Billing::Kv.store.set("organizations:#{@business.id}:ghas_suggestion_flow", "#{org.id}")
      repo = create(:repository, owner: org)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response_not_found
      assert_nil Billing::Kv.store.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
    end

    test "does not updated selected repositories if not authorized" do
      enable_feature_flag(:business_self_serve_recommendation, @business)
      org = create(:organization, business: @business)
      user = create(:user)
      org.add_member(user)
      repo = create(:repository, owner: org)

      as user
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response_not_found
      assert_nil Billing::Kv.store.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
    end
  end if GitHub.billing_enabled?
end
