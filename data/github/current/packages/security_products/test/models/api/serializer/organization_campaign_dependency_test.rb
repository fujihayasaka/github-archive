# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OrganizationCampaignDependencySerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)

    @security_manager_team1 = create(:security_manager_team, organization: @org)
    @security_manager_team2 = create(:security_manager_team, organization: @org)

    @campaign = create(:security_campaign, organization: @org)
  end

  # The `test_helpers/api_serializer_helper` file uses method_missing magic to automatically
  # define these methods just-in-time when they are called. We are defining these
  # methods explicitly, so we can hint to Sorbet that these methods exist.
  def organization_campaign(hash, options)
    method_missing(:organization_campaign, hash, options)
  end

  def organization_campaigns(hash, options)
    method_missing(:organization_campaigns, hash, options)
  end

  context "dotcom", skip_enterprise: true do
    context "#organization_campaign" do
      test "constructs hash for an open campaign" do
        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal @campaign.created_at.iso8601, output["created_at"]
        assert_equal @campaign.updated_at.iso8601, output["updated_at"]
        assert_equal @campaign.name, output["name"]
        assert_equal @campaign.description, output["description"]
        assert_equal 1, output["managers"].size
        assert_equal @campaign.user_manager_users.map(&:id), output["managers"].map { |item| item["id"] }
        assert_equal @campaign.ends_at.iso8601, output["ends_at"]
        assert_equal @campaign.contact_link, output["contact_link"]
        assert_nil output["closed_at"]
        assert_equal "open", output["state"]
        refute output.key?("alert_stats")
      end

      test "constructs hash for a closed campaign" do
        @campaign.update!(closed_at: Time.now)

        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.closed_at.iso8601, output["closed_at"]
        assert_equal "closed", output["state"]
      end

      test "constructs hash with alert stats" do
        campaign_counts = SecurityCampaigns::DetailedCampaignCounts.new(
          open_count: 5,
          closed_count: 10,
          open_with_links_count: 3,
          dismissed_count: 1,
          autofix_supported_count: 5,
          autofix_generated_count: 4,
          autofix_accepted_count: 3
        )
        campaign_with_counts = SecurityCampaigns::CampaignWithCounts.new(@campaign, campaign_counts)

        output = organization_campaign({ campaign: @campaign, campaign_with_counts: campaign_with_counts }, current_user: @owner)

        assert_kind_of Hash, output
        refute_nil output["alert_stats"]
        assert_equal 5, output["alert_stats"]["open_count"]
        assert_equal 10, output["alert_stats"]["closed_count"]
        assert_equal 3, output["alert_stats"]["in_progress_count"]
      end

      test "constructs hash for a campaign with multiple managers" do
        manager = @campaign.user_manager_users.first
        other_manager = create(:user)
        @campaign.update!(user_manager_users: [manager, other_manager])

        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal 2, output["managers"].size
        assert_same_elements [manager.id, other_manager.id], output["managers"].map { |m| m["id"] }
      end

      test "constructs hash for a campaign with team managers" do
        @campaign.update!(team_manager_teams: [@security_manager_team1, @security_manager_team2])

        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal 2, output["team_managers"].size
        assert_same_elements [@security_manager_team1.id, @security_manager_team2.id], output["team_managers"].map { |m| m["id"] }
      end

      test "constructs hash for a campaign without team managers" do
        @campaign.update!(team_manager_teams: [])

        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal 0, output["team_managers"].size
      end

      test "constructs hash for a campaign with secret teams" do
        secret_security_manager_team1 = create(:security_manager_team, organization: @org, privacy: :secret)
        secret_security_manager_team2 = create(:security_manager_team, organization: @org, privacy: :secret)

        security_manager = create(:user).tap { |u| secret_security_manager_team1.add_member(u) }

        @campaign.update!(team_manager_team_ids: [secret_security_manager_team1.id, secret_security_manager_team2.id])
        output = organization_campaign({ campaign: @campaign }, current_user: security_manager)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert_equal 1, output["team_managers"].size
        assert_same_elements [secret_security_manager_team1.id], output["team_managers"].map { |m| m["id"] }
      end

      test "constructs hash for a campaign without a contact link" do
        @campaign.update!(contact_link: nil)

        output = organization_campaign({ campaign: @campaign }, current_user: @owner)

        assert_kind_of Hash, output
        assert_equal @campaign.number, output["number"]
        assert output.key?("contact_link")
        assert_nil output["contact_link"]
      end

      test "does not add alert_stats if there are no alerts" do
        campaign_with_counts = SecurityCampaigns::CampaignWithCounts.new(@campaign, SecurityCampaigns::DetailedCampaignCounts.empty)

        output = organization_campaign({ campaign: @campaign, campaign_with_counts: campaign_with_counts }, current_user: @owner)

        assert_kind_of Hash, output
        refute output.key?("alert_stats")
      end
    end

    context "#organization_campaigns" do
      test "constructs hash for a list of campaigns" do
        campaign1 = create(:security_campaign, organization: @org)
        campaign2 = create(:security_campaign, organization: @org)

        output = organization_campaigns({ campaigns: [campaign1, campaign2], current_user_visible_teams: [] }, current_user: @owner)

        assert_kind_of Array, output
        assert_equal 2, output.size
        assert_equal [campaign1.number, campaign2.number], output.map { |c| c["number"] }
      end

      test "constructs hash for a list of campaigns with campaign counts" do
        campaign1 = create(:security_campaign, organization: @org)
        campaign2 = create(:security_campaign, organization: @org)

        campaigns_with_counts = [
          SecurityCampaigns::CampaignWithCounts.new(campaign1, SecurityCampaigns::DetailedCampaignCounts.new(
            open_count: 5,
            closed_count: 10,
            open_with_links_count: 3,
            dismissed_count: 1,
            autofix_supported_count: 5,
            autofix_generated_count: 4,
            autofix_accepted_count: 3)
          ),
          SecurityCampaigns::CampaignWithCounts.new(campaign2, SecurityCampaigns::DetailedCampaignCounts.new(
            open_count: 3,
            closed_count: 2,
            open_with_links_count: 1,
            dismissed_count: 1,
            autofix_supported_count: 5,
            autofix_generated_count: 4,
            autofix_accepted_count: 3)
          ),
        ]

        output = organization_campaigns({ campaigns: [campaign1, campaign2], campaigns_with_counts:, current_user_visible_teams: [] }, current_user: @owner)

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
