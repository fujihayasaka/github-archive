# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class DraftCreationServiceTest < GitHub::TestCase
    include DogstatsTestHelpers

    # These tests are not compatible with enterprise and
    # the draft creation service should not be used in enterprise
    skip_enterprise

    fixtures do
      GitHub::Enterprise.ensure_business!

      @org = create(:organization)
    end

    setup do
      disable_feature_flag(:security_campaigns_disable)

      @campaign = build(:security_campaign, :draft, organization: @org)
    end

    test "creates draft campaign" do
      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        DraftCreationService.call(campaign: @campaign)
      end
    end

    test "raises an error if the organization has too many draft campaigns" do
      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        (SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT + 1).times do
          campaign = build(:security_campaign, :draft, organization: @org)
          DraftCreationService.call(campaign:)
        end
      end
      assert_equal MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "raises an error if the draft campaigns limit is reached" do
      (SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT).times do
        create(:security_campaign, :draft, organization: @org)
      end

      create(:security_campaign, :draft, organization: @org)

      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        DraftCreationService.call(campaign: @campaign)
      end
      assert_equal MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "does not check open campaigns for draft campaigns limit" do
      (SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, :draft, organization: @org)

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, 1 do
        DraftCreationService.call(campaign: @campaign)
      end
    end
  end
end
