# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class ClosureServiceTest < GitHub::TestCase
    include HydroTestHelpers

    # These tests are not compatible with enterprise and
    # the closure service should not be used in enterprise
    skip_enterprise

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization)
      @open_campaign = create(:security_campaign, organization: @org)
      @closed_campaign = create(:security_campaign, organization: @org, closed_at: Time.now)
    end

    context "call" do
      test "closes a campaign and saves stats" do
        disable_feature_flag(:security_campaigns_disable)

        open_count = 3
        closed_count = 2
        open_with_links_count = 1
        dismissed_count = 1
        autofix_supported_count = 5
        autofix_generated_count = 4
        autofix_accepted_count = 3

        refute @open_campaign.closed?
        GitHub::Turboscan.expects(:counts_by_campaigns).once.with({
          owner_ids: [@org.id],
          security_campaign_ids: [@open_campaign.id],
        }).returns(Twirp::ClientResp.new(
          data: Turboscan::Proto::CountsByCampaignsResponse.new({
            campaign_counts: [
              {
                campaign_id: @open_campaign.id,
                open_count:,
                closed_count:,
                open_with_links_count:,
                dismissed_count:,
                autofix_supported_count:,
                autofix_generated_count:,
                autofix_accepted_count:,
              },
            ]
          })
        ))

        ClosureService.call(campaign: @open_campaign, actor: @current_user, org: @org)

        @open_campaign.reload

        assert @open_campaign.closed?
        assert_equal open_count, @open_campaign.closure_open_count
        assert_equal closed_count, @open_campaign.closure_closed_count
        assert_equal dismissed_count, @open_campaign.closure_dismissed_count
        assert_equal autofix_supported_count, @open_campaign.closure_autofix_supported_count
        assert_equal autofix_generated_count, @open_campaign.closure_autofix_generated_count
        assert_equal autofix_accepted_count, @open_campaign.closure_autofix_accepted_count
      end

      test "publishes a hydro event" do
        refute @open_campaign.closed?

        ClosureService.call(campaign: @open_campaign, actor: @current_user, org: @org)

        @open_campaign.reload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@current_user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          organization: Hydro::EntitySerializer.organization(@org),
          security_campaign: {
            id: @open_campaign.id,
            number: @open_campaign.number,
            name: @open_campaign.name,
            organization_id: @open_campaign.organization_id,
            due_date: @open_campaign.ends_at,
            created_at: @open_campaign.created_at,
            updated_at: @open_campaign.updated_at,
            closed_at: @open_campaign.closed_at,
          },
          user_managers: @open_campaign.user_manager_users.map { |user| Hydro::EntitySerializer.user(user) },
          team_managers: [],
        }, schema: "github.security_campaigns.v0.SecurityCampaignClose")
      end

      test "Enqueues PostCampaignClosedCommentsJob when feature flag is enabled" do
        disable_feature_flag(:security_campaigns_disable)
        enable_feature_flag(:security_campaigns_issue_creation)

        assert_enqueued_jobs(1, only: SecurityCampaigns::PostCampaignClosedCommentsJob) do
          ClosureService.call(campaign: @open_campaign, actor: @current_user, org: @org)
        end
      end

      test "Does not enqueue PostCampaignClosedCommentsJob when campaign issues feature flag is disabled" do
        disable_feature_flag(:security_campaigns_disable)
        disable_feature_flag(:security_campaigns_issue_creation)

        assert_enqueued_jobs(0, only: SecurityCampaigns::PostCampaignClosedCommentsJob) do
          ClosureService.call(campaign: @open_campaign, actor: @current_user, org: @org)
        end
      end
    end
  end
end
