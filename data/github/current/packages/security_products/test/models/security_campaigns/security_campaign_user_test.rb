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
    test "returns the permalink with host for the repository" do
      assert_equal "#{GitHub.url}/orgs/#{@org.display_login}/security/campaigns/#{@campaign.number}", @campaign_user.permalink(include_host: true)
    end

    test "returns the permalink without host for the repository" do
      assert_equal "/orgs/#{@org.display_login}/security/campaigns/#{@campaign.number}", @campaign_user.permalink(include_host: false)
    end

    test "the permalink without the host matches the path helper" do
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
