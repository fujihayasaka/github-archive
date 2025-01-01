# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsRepositoryCountsControllerTest < GitHub::IntegrationTestCase
  # the cassette we use for turboscan contains alerts from two repositories
  # (NB these will currently be returned regardless of the owner_id asked for)
  # the alerts are for repository_id 300 & 351

  fixtures do
    @user = create(:user)
    @unauthed_user = create(:user, skip_enterprise_managed_user: true)

    @org = create(:business_plus_organization, admin: @user)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

    @repo = create(:private_repository, id: 351, from_example: :repository_test_simple, owner: @org)

    @security_campaign_1 = create(:security_campaign, organization: @org)
    @security_campaign_2 = create(:security_campaign, organization: @org)
    @non_repo_security_campaign = create(:security_campaign, organization: @org)

    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign_1, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign_1, logical_alert_number: 6)
    create(:security_campaign_alert, security_campaign: @security_campaign_1, logical_alert_number: 2)
    create(:security_campaign_alert, security_campaign: @security_campaign_1, logical_alert_number: 6)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign_1, logical_alert_number: 20)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign_2, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign_2, logical_alert_number: 2)
    create(:security_campaign_alert, security_campaign: @non_repo_security_campaign, logical_alert_number: 2)
  end

  setup do
    GitHub.flipper[:security_campaigns].enable

    if GitHub.enterprise?
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
    else
      @org.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end

    @repo.enable_advanced_security!(actor: @user)
  end

  context "#index" do
    test "returns 404 when feature flag is disabled" do
      GitHub.flipper[:security_campaigns].disable

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/counts", params: {
        "items" => {
          "item-0" => { "number" => @security_campaign_1.number },
          "item-1" => { "number" => @security_campaign_2.number },
          "item-2" => { "number" => @non_repo_security_campaign.number },
        },
      }, xhr: true

      assert_response_not_found
    end

    test "returns 404 for users that don't have access to the repo" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @unauthed_user
      get "/#{@repo.name_with_display_owner}/security/campaigns/counts", params: {
        "items" => {
          "item-0" => { "number" => @security_campaign_1.number },
          "item-1" => { "number" => @security_campaign_2.number },
        },
      }, xhr: true

      assert_response_not_found
    end

    test "returns 404 for public repository", skip_with_all_emus: true do
      public_repo = create(:public_repository, from_example: :simple, owner: @org)
      create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign_1, logical_alert_number: 5)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      get "/#{public_repo.name_with_display_owner}/security/campaigns/counts", params: {
        "items" => {
          "item-0" => { "number" => @security_campaign_1.number },
        },
      }, xhr: true

      assert_response_not_found
    end

    test "returns 0 for closed campaigns" do
      @security_campaign_1.update(closed_at: Time.now)
      @security_campaign_2.update(closed_at: Time.now)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/counts", params: {
        "items" => {
          "item-0" => { "number" => @security_campaign_1.number },
          "item-1" => { "number" => @security_campaign_2.number },
        },
      }, xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_match "0", payload["item-0"]
      assert_match "0", payload["item-1"]
    end

    test "returns counts" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      VCR.use_cassette("code-scanning/counts-by-repo-numbers", persist_with: :turboscan) do
        get "/#{@repo.name_with_display_owner}/security/campaigns/counts", params: {
          "items" => {
            "item-0" => { "number" => @security_campaign_1.number },
            "item-1" => { "number" => @security_campaign_2.number },
            "item-2" => { "number" => @non_repo_security_campaign.number },
          },
        }, xhr: true
      end

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_match "2", payload["item-0"]
      assert_match "3", payload["item-1"]
      assert_match "0", payload["item-2"]
    end
  end
end
