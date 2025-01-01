# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::SecurityCampaignRepositoryTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)

    @campaign = create(:security_campaign, organization: @org)
    @repo = create(:repository, owner: @org)
    @campaign_repository = create(:security_campaign_repository, repository: @repo, security_campaign: @campaign)
  end

  context "#permalink" do
    test "returns the permalink for the repository" do
      assert_equal "#{@repo.permalink}/security/campaigns/#{@campaign.number}", @campaign_repository.permalink
    end

    test "returns the permalink for the repository when the host is not included" do
      assert_equal "#{@repo.permalink(include_host: false)}/security/campaigns/#{@campaign.number}", @campaign_repository.permalink(include_host: false)
    end

    test "the permalink matches the path helper" do
      assert_equal UrlHelpers.repository_security_campaign_path(repository: @repo, user_id: @repo.owner_display_login, number: @campaign.number), @campaign_repository.permalink(include_host: false)
    end
  end

  context "#message_id" do
    test "returns the message ID for the repository" do
      assert_equal "<#{@repo.name_with_display_owner}/security/campaigns/#{@campaign.number}@#{GitHub.urls.host_name}>", @campaign_repository.message_id
    end
  end

  context "#authzd_attributes" do
    test "returns the permissions wrapper attributes" do
      assert_equal @campaign_repository.permissions_wrapper.serialized_subject_attributes, @campaign_repository.authzd_attributes
    end
  end
end
