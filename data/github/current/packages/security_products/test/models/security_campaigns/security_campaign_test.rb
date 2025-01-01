# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::SecurityCampaignTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
  end

  context "number" do
    test "number starts at 1 for a new org" do
      campaign = create(:security_campaign, organization: @org)
      assert_equal 1, campaign.number
    end

    test "number increments when multiple campaigns are created" do
      campaign1 = create(:security_campaign, organization: @org)
      campaign2 = create(:security_campaign, organization: @org)
      campaign3 = create(:security_campaign, organization: @org)
      assert_equal 1, campaign1.number
      assert_equal 2, campaign2.number
      assert_equal 3, campaign3.number
    end

    test "number sequences are scoped to the organization" do
      org2 = create(:organization, admin: @owner)

      campaign1 = create(:security_campaign, organization: @org)
      campaign2 = create(:security_campaign, organization: @org)

      campaign3 = create(:security_campaign, organization: org2)
      campaign4 = create(:security_campaign, organization: org2)

      assert_equal 1, campaign3.number
      assert_equal 2, campaign4.number
    end

    test "open scope only returns open campaigns" do
      open_campaigns = create_list(:security_campaign, 2, organization: @org)
      create(:security_campaign, organization: @org, closed_at: Time.now)

      assert_equal open_campaigns.map(&:id).sort, SecurityCampaigns::SecurityCampaign.open.map(&:id).sort
    end

    test "closed scope only returns closed campaigns" do
      create_list(:security_campaign, 2, organization: @org)
      closed_campaigns = create_list(:security_campaign, 2, organization: @org, closed_at: Time.now)

      assert_equal closed_campaigns.map(&:id).sort, SecurityCampaigns::SecurityCampaign.closed.map(&:id).sort
    end
  end

  context "#safe_manager" do
    test "returns the manager if the user exists" do
      campaign = create(:security_campaign, organization: @org)

      assert_equal campaign.manager, campaign.safe_manager
    end

    test "returns the ghost user if the user does not exist" do
      user = create(:user)
      campaign = create(:security_campaign, organization: @org, manager: user)
      user.destroy!
      campaign = SecurityCampaigns::SecurityCampaign.find(campaign.id)

      assert_equal User.ghost, campaign.safe_manager
    end
  end
end
