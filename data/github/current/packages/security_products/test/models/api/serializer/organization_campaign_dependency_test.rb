# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OrganizationCampaignDependencySerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)

    @campaign = create(:security_campaign, organization: @org)
  end

  # The `test_helpers/api_serializer_helper` file uses method_missing magic to automatically
  # define these methods just-in-time when they are called. We are defining these
  # methods explicitly, so we can hint to Sorbet that these methods exist.
  def organization_campaign(hash)
    method_missing(:organization_campaign, hash)
  end

  def organization_campaigns(hash)
    method_missing(:organization_campaigns, hash)
  end

  context "dotcom", skip_enterprise: true do
    context "#organization_campaign" do
      test "constructs hash for an open campaign" do
        output = organization_campaign({ campaign: @campaign })

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal @campaign.created_at.iso8601, output["created_at"]
        assert_equal @campaign.updated_at.iso8601, output["updated_at"]
        assert_equal @campaign.name, output["name"]
        assert_equal @campaign.description, output["description"]
        assert_equal 1, output["managers"].size
        assert_equal @campaign.manager.id, output["managers"].first["id"]
        assert_equal @campaign.ends_at.iso8601, output["ends_at"]
        assert_nil output["closed_at"]
        assert_equal "open", output["state"]
        refute output.key?("alert_stats")
      end

      test "constructs hash for a closed campaign" do
        @campaign.update!(closed_at: Time.now)

        output = organization_campaign({ campaign: @campaign })

        assert_kind_of Hash, output
        assert_equal @campaign.closed_at.iso8601, output["closed_at"]
        assert_equal "closed", output["state"]
      end

      test "constructs hash with alert stats" do
        campaign_with_counts = SecurityCampaigns::CampaignWithCounts.new(@campaign, 5, 10, 3)

        output = organization_campaign({ campaign: @campaign, campaign_with_counts: campaign_with_counts })

        assert_kind_of Hash, output
        refute_nil output["alert_stats"]
        assert_equal 5, output["alert_stats"]["open_count"]
        assert_equal 10, output["alert_stats"]["closed_count"]
        assert_equal 3, output["alert_stats"]["in_progress_count"]
      end

      test "does not add alert_stats if there are no alerts" do
        campaign_with_counts = SecurityCampaigns::CampaignWithCounts.new(@campaign, 0, 0, 0)

        output = organization_campaign({ campaign: @campaign, campaign_with_counts: campaign_with_counts })

        assert_kind_of Hash, output
        refute output.key?("alert_stats")
      end
    end

    context "#organization_campaigns" do
      test "constructs hash for a list of campaigns" do
        campaign1 = create(:security_campaign, organization: @org)
        campaign2 = create(:security_campaign, organization: @org)

        output = organization_campaigns({ campaigns: [campaign1, campaign2] })

        assert_kind_of Array, output
        assert_equal 2, output.size
        assert_equal [campaign1.number, campaign2.number], output.map { |c| c["number"] }
      end

      test "constructs hash for a list of campaigns with campaign counts" do
        campaign1 = create(:security_campaign, organization: @org)
        campaign2 = create(:security_campaign, organization: @org)

        campaigns_with_counts = [
          SecurityCampaigns::CampaignWithCounts.new(campaign1, 5, 10, 3),
          SecurityCampaigns::CampaignWithCounts.new(campaign2, 3, 2, 1),
        ]

        output = organization_campaigns({ campaigns: [campaign1, campaign2], campaigns_with_counts: })

        assert_kind_of Array, output
        assert_equal 2, output.size
        assert_equal [campaign1.number, campaign2.number], output.map { |c| c["number"] }
        refute_nil output.first["alert_stats"]
        assert_equal 5, output.first["alert_stats"]["open_count"]
        assert_equal 10, output.first["alert_stats"]["closed_count"]
        assert_equal 3, output.first["alert_stats"]["in_progress_count"]
        refute_nil output.last["alert_stats"]
        assert_equal 3, output.last["alert_stats"]["open_count"]
        assert_equal 2, output.last["alert_stats"]["closed_count"]
        assert_equal 1, output.last["alert_stats"]["in_progress_count"]
      end
    end
  end
end
