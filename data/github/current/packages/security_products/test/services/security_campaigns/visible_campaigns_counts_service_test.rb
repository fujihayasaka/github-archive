# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::VisibleCampaignsCountsTestService < GitHub::TestCase
  include ::SecurityCenter::TurboscanTestSetup

  setup do
    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @member = create(:user).tap { |u| @org.add_member(u) }

    @repo = create(:private_repository, owner: @org, from_example: :simple)
    # add member as write to repo
    @repo.add_member(@member, action: :write)

    @campaign1 = create(:security_campaign, organization: @org)
    @campaign2 = create(:security_campaign, organization: @org)
    @campaign3 = create(:security_campaign, organization: @org)
    create(:security_campaign, :draft, organization: @org)
    create(:security_campaign, organization: @org, closed_at: Time.now)
  end

  context "#call" do
    test "returns all counts when user is an owner" do
      default_alerts_filter = @default_alerts_filter
      # Open campaigns
      GitHub::Turboscan
      .expects(:total_counts_for_campaigns)
      .with({
        owner_ids: [@org.id],
        filter: default_alerts_filter.merge(
          security_campaign_ids: [@campaign1.id, @campaign2.id, @campaign3.id],
        )
      }).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::TotalCountsForCampaignsResponse.new(
            open_count: 7,
            open_with_links_count: 5,
            closed_count: 13,
            dismissed_count: 11,
            autofix_supported_count: 20,
            autofix_generated_count: 15,
            autofix_accepted_count: 2,
          )
        )
      )
      # Closed campaigns
      GitHub::Turboscan
      .expects(:total_counts_for_campaigns)
      .with({
        owner_ids: [@org.id],
        filter: default_alerts_filter.merge(
          excluded_security_campaign_ids: [@campaign1.id, @campaign2.id, @campaign3.id],
          campaign_presence: :CAMPAIGN_PRESENCE_IN_CAMPAIGN
        )
      }).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::TotalCountsForCampaignsResponse.new(
            open_count: 3,
            open_with_links_count: 1,
            closed_count: 25,
            dismissed_count: 16,
            autofix_supported_count: 26,
            autofix_generated_count: 20,
            autofix_accepted_count: 5,
          )
        )
      )

      result = SecurityCampaigns::VisibleCampaignsCountsService.call(
        org: @org,
        user: @owner,
        allowed_repository_ids: [],
        can_manage_security_products: true
      )

      expected = SecurityCampaigns::VisibleCampaignsCounts.new(
        open_campaigns_count: 3,
        open_campaigns_total_count: 20,
        open_campaigns_open_count: 7,
        open_campaigns_in_progress_count: 5,
        open_campaigns_fixed_count: 2,
        open_campaigns_dismissed_count: 11,
        closed_campaigns_count: 1,
        closed_campaigns_total_count: 28,
        closed_campaigns_open_count: 3,
        closed_campaigns_fixed_count: 9,
        closed_campaigns_dismissed_count: 16,
        draft_campaigns_count: 1,
        autofix_generated_count: 35,
        autofix_applied_count: 7,
      )

      assert_equal result.instance_values, expected.instance_values
    end

    test "returns only data visible to the user" do
      default_alerts_filter = @default_alerts_filter

      # The total count endpoint is not called for regular members
      GitHub::Turboscan.expects(:total_counts_for_campaigns).never
      # Called to check which campaigns should be shown to the user
      GitHub::Turboscan.expects(:counts_by_campaigns).with({
        owner_ids: [@org.id],
        security_campaign_ids: [@campaign1.id, @campaign2.id, @campaign3.id].sort,
        repository_ids: [@repo.id], # Only repo should be included because the user has access to it
      }).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CountsByCampaignsResponse.new({
          campaign_counts: [
            {
              campaign_id: @campaign1.id,
              open_count: 3,
              closed_count: 2,
              open_with_links_count: 1,
            },
          ]
        })
      ))

      result = SecurityCampaigns::VisibleCampaignsCountsService.call(
        org: @org,
        user: @member,
        allowed_repository_ids: [@repo.id],
        can_manage_security_products: false
      )
      expected = SecurityCampaigns::VisibleCampaignsCounts.new(
        open_campaigns_count: 1,
        open_campaigns_total_count: 0,
        open_campaigns_open_count: 0,
        open_campaigns_in_progress_count: 0,
        open_campaigns_fixed_count: 0,
        open_campaigns_dismissed_count: 0,
        closed_campaigns_count: 0,
        closed_campaigns_total_count: 0,
        closed_campaigns_open_count: 0,
        closed_campaigns_fixed_count: 0,
        closed_campaigns_dismissed_count: 0,
        draft_campaigns_count: 1,
        autofix_generated_count: 0,
        autofix_applied_count: 0,
      )

      assert_equal result.instance_values, expected.instance_values
    end
  end
end
