# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class OpeningServiceTest < GitHub::TestCase
    include HydroTestHelpers
    include DogstatsTestHelpers

    # These tests are not compatible with enterprise and
    # the opening service should not be used in enterprise
    skip_enterprise

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization, admin: @manager)

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)

      @team1 = create(:security_manager_team)
      @team2 = create(:security_manager_team)

      @query_string = "is:open"
    end

    setup do
      disable_feature_flag(:security_campaigns_disable)

      reset_redis_rate_limiter
      reset_monolith_redis_rate_limiter

      @logical_alert_info = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
        @repo2.id => [Turboscan::Proto::Result.new(number: 3, tool: { name: "CodeQL" })]
      }
      @opening_details = build(:security_campaign_opening_details, org: @org, alerts: @logical_alert_info, managers: [@manager], query_string: @query_string)
      @campaign = SecurityCampaign.from_opening_details(@opening_details, Time.zone.now)
      @campaign.save

      GitHub::Turboscan
      .stubs(:create_security_campaign_alerts)
      .returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::CreateSecurityCampaignAlertsResponse.new
        )
      )
    end

    test "creates alerts in turboscan" do
      GitHub::Turboscan
      .expects(:create_security_campaign_alerts)
      .once
      .with(
        security_campaign_id: @campaign.id,
        repo_numbers: [
          {
            repository_id: @repo1.id,
            number: 1,
          },
          {
            repository_id: @repo1.id,
            number: 2,
          },
          {
            repository_id: @repo2.id,
            number: 3,
          }
        ]
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::CreateSecurityCampaignAlertsResponse.new
        )
      )

      OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
    end

    test "instruments to notifications" do
      GlobalInstrumenter.expects(:instrument).with("security_campaigns.security_campaign_create", anything).once

      OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
    end

    test "publishes a telemetry hydro event" do
      @opening_details.alerts = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
        @repo2.id => [Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 3, tool: { name: "CodeQL" })]
      }
      campaign = OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@current_user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        query: @query_string,
        repo_count: 2,
        alert_count: 4,
        organization: Hydro::EntitySerializer.organization(@org),
        description: @campaign.description,
        security_campaign: {
          id: campaign.id,
          number: campaign.number,
          name: campaign.name,
          organization_id: campaign.organization_id,
          due_date: campaign.ends_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at,
          closed_at: campaign.closed_at,
        },
        user_managers: [Hydro::EntitySerializer.user(@manager)],
        team_managers: [],
      }, schema: "github.security_campaigns.v0.SecurityCampaignCreate")
    end

    test "publishes a telemetry hydro event with team managers" do
      @campaign.team_manager_team_ids = [@team1.id, @team2.id]
      campaign = OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)

      assert_hydro_published_partial({
        user_managers: [Hydro::EntitySerializer.user(@manager)],
        team_managers: [Hydro::EntitySerializer.team(@team1), Hydro::EntitySerializer.team(@team2)],
      }, schema: "github.security_campaigns.v0.SecurityCampaignCreate")
    end

    test "enqueues autofix job" do
      @opening_details.alerts = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
      }

      assert_enqueued_jobs(1, only: SecurityCampaigns::GenerateAutofixesJob) do
        assert_enqueued_with(job: SecurityCampaigns::GenerateAutofixesJob, args: proc {
          |args| args[0][:logical_alert_info] == [{ repo_id: @repo1.id, alerts: [{ alert_number: 1, tool_name: "CodeQL" }, { alert_number: 2, tool_name: "CodeQL" }] }] && args[0][:generate_autofix_pull_requests] == false
        }) do
          OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
        end
      end
    end

    test "enqueues autofix job when generate autofix pull requests is enabled and feature flag is disabled" do
      disable_feature_flag(:security_campaigns_autofix_pr_creation)

      @opening_details.alerts = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
      }
      @opening_details.generate_autofix_pull_requests = true

      assert_enqueued_with(job: SecurityCampaigns::GenerateAutofixesJob, args: proc {
        |args| args[0][:logical_alert_info] == [{ repo_id: @repo1.id, alerts: [{ alert_number: 1, tool_name: "CodeQL" }, { alert_number: 2, tool_name: "CodeQL" }] }] && args[0][:generate_autofix_pull_requests] == false
      }) do
        OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
      end
    end

    test "enqueues autofix job when generate autofix pull requests is enabled and feature flag is enabled" do
      enable_feature_flag(:security_campaigns_autofix_pr_creation, @org)

      @opening_details.alerts = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
      }
      @opening_details.generate_autofix_pull_requests = true

      assert_enqueued_with(job: SecurityCampaigns::GenerateAutofixesJob, args: proc {
        |args| args[0][:logical_alert_info] == [{ repo_id: @repo1.id, alerts: [{ alert_number: 1, tool_name: "CodeQL" }, { alert_number: 2, tool_name: "CodeQL" }] }] && args[0][:generate_autofix_pull_requests] == true
      }) do
        OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
      end
    end

    test "enqueues a job to create SecurityCampaignUser records" do
      assert_enqueued_jobs 1, only: SendCreationNotificationJob do
        OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
      end
    end

    test "raises error if turboscan fails to create security campaign alerts" do
      GitHub::Turboscan
      .expects(:create_security_campaign_alerts)
      .once
      .returns(
        Twirp::ClientResp.new(data: nil)
      )

      assert_raises(TurboscanError) do
        OpeningService.call(campaign: @campaign, opening_details: @opening_details, actor: @current_user)
      end
    end
  end
end
