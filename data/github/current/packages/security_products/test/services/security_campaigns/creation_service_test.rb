# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class CreationServiceTest < GitHub::TestCase
    include DogstatsTestHelpers

    # These tests are not compatible with enterprise and
    # the creation service should not be used in enterprise
    skip_enterprise

    fixtures do
      GitHub::Enterprise.ensure_business!

      @manager = create(:user)
      @current_user = create(:user)

      @org = create(:organization, admin: @manager)

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)

      @query_string = "is:open"
    end

    setup do
      disable_feature_flag(:security_campaigns_disable)

      @logical_alert_info = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
        @repo2.id => [Turboscan::Proto::Result.new(number: 3, tool: { name: "CodeQL" })]
      }
      @opening_details = build(:security_campaign_opening_details, org: @org, alerts: @logical_alert_info, managers: [@manager], query_string: @query_string)

      GitHub::Turboscan
      .stubs(:create_security_campaign_alerts)
      .returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::CreateSecurityCampaignAlertsResponse.new
        )
      )
    end

    test "creates campaign" do
      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        CreationService.call(opening_details: @opening_details, actor: @current_user)
      end
    end

    test "raises an error if the organization has too many campaigns" do
      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        (SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT + 1).times do
          CreationService.call(opening_details: @opening_details, actor: @current_user)
        end
      end
      assert_equal MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "raises an error if the open campaigns limit is reached" do
      (SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        CreationService.call(opening_details: @opening_details, actor: @current_user)
      end
      assert_equal MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "raises an error if the rate limit is exceeded" do
      enable_content_creation_rate_limiting

      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]

      Timecop.freeze do
        10.times do
          campaign = build(:security_campaign, organization: @org, user_manager_users: [@manager])
          campaign.check_creation_rate_limit
        end

        campaign = build(:security_campaign, organization: @org, user_manager_users: [@manager])
        error = assert_raises(ActiveRecord::RecordInvalid, expected_errors) do
          CreationService.call(opening_details: @opening_details, actor: @current_user)
        end

        assert_equal expected_errors, error.record.errors.full_messages
      end

      assert_dogstats_increment(
        "rate_limited_creation",
        tags: ["subject:security_campaigns/security_campaign", "name:per_user_minute", "config_type:dynamic", "skip_increment:false"]
      )
    end

    test "does not check closed campaigns for campaigns limit" do
      (SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT - 1).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, 1 do
        CreationService.call(opening_details: @opening_details, actor: @current_user)
      end
    end

    test "calls the opening service" do
      SecurityCampaigns::OpeningService
        .expects(:call)
        .with(
          campaign: instance_of(SecurityCampaigns::SecurityCampaign),
          opening_details: @opening_details,
          actor: @current_user,
        )

      CreationService.call(
        opening_details: @opening_details,
        actor: @current_user,
      )
    end
  end
end
