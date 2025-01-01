# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsAlertsControllerTest < GitHub::IntegrationTestCase
  include ::SecurityCenter::TurboscanTestSetup
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @unauthed_user = create(:user, skip_enterprise_managed_user: true)

    @org = create(:business_plus_organization, admin: @user)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

    @repo = create(:private_repository, owner: @org, from_example: :simple)

    @security_campaign = create(:security_campaign, organization: @org)

    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 6)
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

    @close_params = {
      "alert_numbers" => [2, 6],
      "resolution" => "false_positive",
      "dismissal_comment" => "blah blah blah",
    }
  end

  context "#index" do
    test "returns successfully when user has write access to repo" do
      GitHub::Turboscan.expects(:alerts_by_repo).once.with(@default_alerts_by_repo_args.merge({
        owner_ids: [@org.id],
        repository_ids: [@repo.id],
        repository_visibilities: SecurityCampaigns::TURBOSCAN_REPOSITORY_VISIBILITIES_SYMBOLS,
        repo_numbers: [Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo.id,
        }), Turboscan::Proto::RepoNumber.new({
          number: 6,
          repository_id: @repo.id,
        })].map(&:to_h),
        limit: SecurityCampaigns::CampaignWithAlerts::page_size,
      })).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new({
          results: [],
          open_count: 533,
          resolved_count: 10_235,
          next_cursor: "cursor1",
          prev_cursor: "cursor0",
        })
      ))

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_success

      payload = JSON.parse(response.body)
      assert_equal ({
        "alerts" => [],
        "openCount" => 533,
        "closedCount" => 10_235,
        "nextCursor" => "cursor1",
        "prevCursor" => "cursor0",
      }), payload
    end

    test "passes through filters" do
      GitHub::Turboscan.expects(:alerts_by_repo).once.with(@default_alerts_by_repo_args.merge({
        owner_ids: [@org.id],
        repository_ids: [@repo.id],
        repository_visibilities: SecurityCampaigns::TURBOSCAN_REPOSITORY_VISIBILITIES_SYMBOLS,
        rule_sarif_identifiers: ["java/log-injection"],
        repo_numbers: [Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo.id,
        }), Turboscan::Proto::RepoNumber.new({
          number: 6,
          repository_id: @repo.id,
        })].map(&:to_h),
        limit: SecurityCampaigns::CampaignWithAlerts::page_size,
      })).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new({
          results: [],
        })
      ))

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts?query=rule%3Ajava%2Flog-injection", params: {}, xhr: true

      assert_response_success

      payload = JSON.parse(response.body)
      assert_equal %w[alerts openCount closedCount nextCursor prevCursor], payload.keys
      assert_equal 0, payload["alerts"].size
    end

    test "passes through after cursor" do
      GitHub::Turboscan.expects(:alerts_by_repo).once.with(@default_alerts_by_repo_args.merge({
        owner_ids: [@org.id],
        repository_ids: [@repo.id],
        repository_visibilities: SecurityCampaigns::TURBOSCAN_REPOSITORY_VISIBILITIES_SYMBOLS,
        repo_numbers: [Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo.id,
        }), Turboscan::Proto::RepoNumber.new({
          number: 6,
          repository_id: @repo.id,
        })].map(&:to_h),
        limit: SecurityCampaigns::CampaignWithAlerts::page_size,
        after_cursor: "cursor1",
      })).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new({
          results: [],
        })
      ))

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts?after=cursor1", params: {}, xhr: true

      assert_response_success

      payload = JSON.parse(response.body)
      assert_equal %w[alerts openCount closedCount nextCursor prevCursor], payload.keys
      assert_equal 0, payload["alerts"].size
    end

    test "passes through before cursor" do
      GitHub::Turboscan.expects(:alerts_by_repo).once.with(@default_alerts_by_repo_args.merge({
        owner_ids: [@org.id],
        repository_ids: [@repo.id],
        repository_visibilities: SecurityCampaigns::TURBOSCAN_REPOSITORY_VISIBILITIES_SYMBOLS,
        repo_numbers: [Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo.id,
        }), Turboscan::Proto::RepoNumber.new({
          number: 6,
          repository_id: @repo.id,
        })].map(&:to_h),
        limit: SecurityCampaigns::CampaignWithAlerts::page_size,
        before_cursor: "cursor2",
      })).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new({
          results: [],
        })
      ))

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts?before=cursor2", params: {}, xhr: true

      assert_response_success

      payload = JSON.parse(response.body)
      assert_equal %w[alerts openCount closedCount nextCursor prevCursor], payload.keys
      assert_equal 0, payload["alerts"].size
    end

    test "filters are accepted by turboscan" do
      # We dont need to test autofix here
      CodeScanning::Autofix.stubs(:suggested_fixes_for_alerts).returns({})
      GitHub::Turboscan.stubs(:get_links_for_alerts).returns({})

      as @user
      VCR.use_cassette("code-scanning/org-alerts", persist_with: :turboscan) do
        get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts?query=rule%3Ajava%2Flog-injection", params: {}, xhr: true
      end

      assert_response_success
    end

    test "returns 404 when feature flag is disabled" do
      GitHub.flipper[:security_campaigns].disable

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 when advanced security is disabled" do
      @repo.disable_advanced_security!(actor: @user)

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 for public repository", skip_with_all_emus: true do
      public_repo = create(:public_repository, from_example: :simple, owner: @org)
      create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign, logical_alert_number: 5)

      as @user
      get "/#{public_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 for closed campaign" do
      @security_campaign.update(closed_at: Time.now)

      as @user
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end


    test "returns 404 when user only has read access to repo" do
      readonly_collaborator = create(:user)
      @repo.add_member(readonly_collaborator, action: :read)

      as readonly_collaborator
      get "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 trying to access campaign from wrong repo in different org" do
      other_org = create(:business_plus_organization, admin: @user)
      other_org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

      other_repo = create(:private_repository, from_example: :simple, owner: other_org)
      other_repo.enable_advanced_security!(actor: @user)

      as @user
      get "/#{other_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end

    test "returns 404 trying to access campaign from wrong repo in same org" do
      other_repo = create(:private_repository, from_example: :simple, owner: @org)
      other_repo.enable_advanced_security!(actor: @user)

      as @user
      get "/#{other_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: {}, xhr: true

      assert_response_not_found
    end
  end

  context "#close" do
    test "returns 404 when feature flag is disabled" do
      GitHub.flipper[:security_campaigns].disable

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params, xhr: true

      assert_response_not_found
    end

    test "returns 404 for users that don't have access to the repo" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @unauthed_user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params, xhr: true

      assert_response_not_found
    end

    test "returns 404 for public repository", skip_with_all_emus: true do
      public_repo = create(:public_repository, from_example: :simple, owner: @org)
      create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign, logical_alert_number: 5)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{public_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @close_params, xhr: true

      assert_response_not_found
    end

    test "dismisses alerts and shows plural flash notice" do
      response = Twirp::ClientResp.new(error: nil)
      GitHub::Turboscan.expects(:set_alerts_status).once.with({
        repository_id: @repo.id,
        resolution: ::Turboscan::Proto::ResultResolution::FALSE_POSITIVE,
        resolver_id: @user.id,
        resolution_note: "blah blah blah",
        numbers: [2, 6],
        ref_names_bytes: ["refs/heads/master"],
      }).returns(response)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params, xhr: true

      assert_response :ok
      assert_equal "2 alerts were closed successfully", flash[:notice]
    end

    test "dismisses alert and shows singular flash notice" do
      response = Twirp::ClientResp.new(error: nil)
      GitHub::Turboscan.expects(:set_alerts_status).once.with({
        repository_id: @repo.id,
        resolution: ::Turboscan::Proto::ResultResolution::FALSE_POSITIVE,
        resolver_id: @user.id,
        resolution_note: "blah blah blah",
        numbers: [2],
        ref_names_bytes: ["refs/heads/master"],
      }).returns(response)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => [2]
      }), xhr: true

      assert_response :ok
      assert_equal "1 alert was closed successfully", flash[:notice]
    end

    test "dismisses alerts when dismissal comment is empty" do
      response = Twirp::ClientResp.new(error: nil)
      GitHub::Turboscan.expects(:set_alerts_status).once.with({
        repository_id: @repo.id,
        resolution: ::Turboscan::Proto::ResultResolution::FALSE_POSITIVE,
        resolver_id: @user.id,
        resolution_note: nil,
        numbers: [2, 6],
        ref_names_bytes: ["refs/heads/master"],
      }).returns(response)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.except("dismissal_comment"), xhr: true

      assert_response :ok
    end

    test "dismisses alerts and logs analytics event", skip_enterprise: true do
      response = Twirp::ClientResp.new(error: nil)
      GitHub::Turboscan.expects(:set_alerts_status).once.with({
        repository_id: @repo.id,
        resolution: ::Turboscan::Proto::ResultResolution::FALSE_POSITIVE,
        resolver_id: @user.id,
        resolution_note: nil,
        numbers: [2, 6],
        ref_names_bytes: ["refs/heads/master"],
      }).returns(response)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.except("dismissal_comment"), xhr: true

      assert_response :ok

      assert_hydro_published_partial({
        category: "security_campaigns",
        action: "close_alerts",
        label: "security_campaign_id:#{@security_campaign.id}; resolution:false_positive; alert_numbers_count:2"
      }, schema: "github.analytics.v0.Event")
    end

    test "returns 422 when campaign is already closed" do
      @security_campaign.update(closed_at: Time.now)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params, xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Campaign is already closed", payload["message"]
    end

    test "returns 422 when the alert numbers are not an array" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => 1
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Alert numbers are required", payload["message"]
    end

    test "returns 422 when the alert numbers are strings" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => %w[foo bar]
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Invalid alert numbers", payload["message"]
    end

    test "returns 422 when the alert numbers are negative numbers" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => ["-1", 2, "4"]
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Invalid alert numbers", payload["message"]
    end

    test "returns 422 when the resolution reason is empty" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "resolution" => ""
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Resolution reason is required", payload["message"]
    end

    test "returns 400 when the resolution reason is present but invalid" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "resolution" => "foo"
      }), xhr: true

      assert_response :bad_request

      payload = JSON.parse(response.body)
      assert_equal "Resolution reason is not valid", payload["message"]
    end

    test "returns 422 when the default branch does not exist" do
      empty_repo = create(:private_repository, owner: @org)
      empty_repo.enable_advanced_security!(actor: @user)

      create(:security_campaign_alert, repository: empty_repo, security_campaign: @security_campaign, logical_alert_number: 2)
      create(:security_campaign_alert, repository: empty_repo, security_campaign: @security_campaign, logical_alert_number: 6)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{empty_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params, xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Default branch must exist", payload["message"]
    end

    test "returns 400 when the dismissal comment in invalid" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "dismissal_comment" => "a" * 1000
      }), xhr: true

      assert_response :bad_request

      payload = JSON.parse(response.body)
      assert_equal "Alert dismissal comment is not valid", payload["message"]
    end

    test "returns 400 when given alert numbers that do not exist" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => [2, 6, 1234]
      }), xhr: true

      assert_response :bad_request

      payload = JSON.parse(response.body)
      assert_equal "Alert numbers are not valid", payload["message"]
    end

    test "returns 400 when given alert numbers that are from another campaign" do
      another_alert = create(:security_campaign_alert, repository: @repo, logical_alert_number: 99)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/alerts", params: @close_params.merge({
        "alert_numbers" => [2, 6, another_alert.logical_alert_number]
      }), xhr: true

      assert_response :bad_request

      payload = JSON.parse(response.body)
      assert_equal "Alert numbers are not valid", payload["message"]
    end
  end
end
