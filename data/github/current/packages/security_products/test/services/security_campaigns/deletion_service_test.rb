# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class DeletionServiceTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization)
      @team = create(:team, organization: @org)
      @campaign = create(:security_campaign, organization: @org, user_manager_users: [@manager], team_manager_teams: [@team], contact_link: "https://example.com")

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)

      create(:security_campaign_user, security_campaign: @campaign)
      create(:security_campaign_user, security_campaign: @campaign)

      @campaign_issue1 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo1)
      @campaign_issue2 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo2)
    end

    test "publishes a telemetry hydro event" do
      campaign = DeletionService.call(campaign: @campaign,  actor: @current_user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@current_user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@org),
        security_campaign: {
          id: @campaign.id,
          number: @campaign.number,
          name: @campaign.name,
          organization_id: @campaign.organization_id,
          due_date: @campaign.ends_at,
          created_at: @campaign.created_at,
          updated_at: @campaign.updated_at,
          closed_at: @campaign.closed_at,
        },
        user_managers: [Hydro::EntitySerializer.user(@manager)],
        team_managers: [Hydro::EntitySerializer.team(@team)],
      }, schema: "github.security_campaigns.v0.SecurityCampaignDelete")
    end

    test "deletes security campaign, other related data, and alerts from turboscan" do
      GitHub::Turboscan
      .expects(:delete_security_campaign_alerts)
      .once
      .with(
        security_campaign_id: @campaign.id,
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::CreateSecurityCampaignAlertsResponse.new
        )
      )

      refute_nil SecurityCampaign.find_by(id: @campaign.id)

      assert_difference({
        "SecurityCampaigns::SecurityCampaign.count" => -1,
        "SecurityCampaigns::SecurityCampaignUserManager.count" => -1,
        "SecurityCampaigns::SecurityCampaignTeamManager.count" => -1,
        "SecurityCampaigns::SecurityCampaignUser.count" => -2,
        "SecurityCampaigns::SecurityCampaignIssue.count" => -2,
        "Issue.count" => 0,
        "User.count" => 0,
        "Team.count" => 0,
      }) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          DeletionService.call(campaign: @campaign, actor: @current_user)
        end
      end

      assert_nil SecurityCampaign.find_by(id: @campaign.id)
    end

    context "post comments to issues", skip_enterprise: true, skip_in_multitenant_mode: true do
      test "enqueues job to post campaign deleted comments to issues when feature flag is enabled" do
        disable_feature_flag(:security_campaigns_disable, @org)
        enable_feature_flag(:security_campaigns_issue_creation, @org)

        expected_args = ->(job_args) do
          assert_equal({
            deleted_campaign_id: @campaign.id,
            org_id: @campaign.organization_id,
            actor_id: @current_user.id,
            contact_link_present: true,
          }, job_args[0].except(:issue_ids))
          assert_same_elements [@campaign_issue1.issue_id, @campaign_issue2.issue_id], job_args[0][:issue_ids]
        end

        assert_enqueued_with(job: SecurityCampaigns::PostCampaignDeletedCommentsJob, args: expected_args) do
          DeletionService.call(campaign: @campaign, actor: @current_user)
        end
      end

      test "doesn't enqueue job to post campaign deleted comments to issues when feature flag is disabled" do
        disable_feature_flag(:security_campaigns_disable, @org)
        disable_feature_flag(:security_campaigns_issue_creation, @org)

        assert_enqueued_jobs(0, only: SecurityCampaigns::PostCampaignDeletedCommentsJob) do
          DeletionService.call(campaign: @campaign, actor: @current_user)
        end
      end

      test "handles transferred issues" do
        disable_feature_flag(:security_campaigns_disable, @org)
        enable_feature_flag(:security_campaigns_issue_creation, @org)

        transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo2, actor: @org.admin)
        transfer.transfer!

        expected_args = ->(job_args) do
          assert_same_elements [@campaign_issue2.issue_id, transfer.new_issue_id], job_args[0][:issue_ids]
        end

        assert_enqueued_with(job: SecurityCampaigns::PostCampaignDeletedCommentsJob, args: expected_args) do
          DeletionService.call(campaign: @campaign, actor: @current_user)
        end
      end
    end
  end
end
