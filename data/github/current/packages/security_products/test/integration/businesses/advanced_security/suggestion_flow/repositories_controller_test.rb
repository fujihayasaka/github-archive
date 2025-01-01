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
      GitHub.flipper[:ghas_self_serve_recommendation].enable(@business)
      org = create(:organization, business: @business)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set("organizations:#{@business.id}:ghas_suggestion_flow", "#{org.id}")
      # rubocop:enable GitHub/DoNotUseGlobalKv
      repo = create(:repository, owner: org)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response :success
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_equal [repo.id].join(","), GitHub.kv.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "404 if FF is not enabled" do
      GitHub.flipper[:ghas_self_serve_recommendation].disable(@business)
      org = create(:organization, business: @business)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set("organizations:#{@business.id}:ghas_suggestion_flow", "#{org.id}")
      # rubocop:enable GitHub/DoNotUseGlobalKv
      repo = create(:repository, owner: org)

      as @owner
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response_not_found
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "does not updated selected repositories if not authorized" do
      GitHub.flipper[:business_self_serve_recommendation].enable(@business)
      org = create(:organization, business: @business)
      user = create(:user)
      org.add_member(user)
      repo = create(:repository, owner: org)

      as user
      put "/enterprises/#{@business.to_param}/settings/advanced_security/suggestion_flow/repositories",
        params: { selected_repo_ids: [repo.id] }, xhr: true

      assert_response_not_found
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get("repositories:#{@business.id}:ghas_suggestion_flow").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end if GitHub.billing_enabled?
end
