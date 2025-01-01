# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::SecurityCampaignUserTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)

    @campaign = create(:security_campaign, organization: @org)
    @repo = create(:repository, owner: @org)
    @campaign_user = create(:security_campaign_user, security_campaign: @campaign)
  end

  context "#permalink" do
    test "returns the permalink for the repository" do
      assert_equal "/orgs#{@campaign.organization.permalink}/security/campaigns/#{@campaign.number}", @campaign_user.permalink
    end

    test "returns the permalink for the repository when the host is not included" do
      assert_equal "/orgs#{@campaign.organization.permalink(include_host: false)}/security/campaigns/#{@campaign.number}", @campaign_user.permalink(include_host: false)
    end

    test "the permalink matches the path helper" do
      assert_equal UrlHelpers.security_center_security_campaign_path(org: @org, number: @campaign.number), @campaign_user.permalink(include_host: false)
    end
  end

  context "#message_id" do
    test "returns the message ID for the repository" do
      assert_equal "<#{@campaign.organization.name_with_display_owner}/security/campaigns/#{@campaign.number}@#{GitHub.urls.host_name}>", @campaign_user.message_id
    end
  end

  context "#authzd_attributes" do
    test "returns the permissions wrapper attributes" do
      assert_equal @campaign_user.permissions_wrapper.serialized_subject_attributes, @campaign_user.authzd_attributes
    end
  end
end
