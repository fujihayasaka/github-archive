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
      @campaign = create(:security_campaign, organization: @org, manager: @manager)

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)

      @campaign_repo1 = create(:security_campaign_repository, repository: @repo1, security_campaign: @campaign)
      @campaign_repo2 = create(:security_campaign_repository, repository: @repo2, security_campaign: @campaign)

      create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 1)
      create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 2)
      create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 10)
      create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 20)
    end

    test "deletes campaign and associated repositories and alerts" do
      foo = SecurityCampaign.where(id: @campaign.id)
      refute_nil foo
      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 1, to: 0 do
        assert_changes -> { SecurityCampaigns::SecurityCampaignRepository.count }, from: 2, to: 0 do
          assert_changes -> { SecurityCampaigns::SecurityCampaignAlert.count }, from: 4, to: 0 do
            DeletionService.call(campaign: @campaign, actor: @current_user)
          end
        end
      end
    end

    test "publishes a telemetry hydro event" do
      campaign = DeletionService.call(campaign: @campaign,  actor: @current_user)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@current_user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@org),
        manager: Hydro::EntitySerializer.user(@manager),
        security_campaign: {
          id: @campaign.id,
          number: @campaign.number,
          name: @campaign.name,
          organization_id: @campaign.organization_id,
          manager_id: @campaign.manager_id,
          due_date: @campaign.ends_at,
          created_at: @campaign.created_at,
          updated_at: @campaign.updated_at,
          closed_at: @campaign.closed_at,
        }
      }, schema: "github.security_campaigns.v0.SecurityCampaignDelete")
    end
  end
end
