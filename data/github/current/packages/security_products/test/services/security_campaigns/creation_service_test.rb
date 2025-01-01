# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class CreationServiceTest < GitHub::TestCase
    include HydroTestHelpers
    include DogstatsTestHelpers

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
      GitHub.flipper[:security_campaigns_one_email_per_campaign].disable
      GitHub.flipper[:security_campaigns_rate_limited_creation].disable

      reset_redis_rate_limiter
      reset_monolith_redis_rate_limiter

      @logical_alert_info = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
        @repo2.id => [Turboscan::Proto::Result.new(number: 3, tool: { name: "CodeQL" })]
      }
      @campaign = build(:security_campaign, organization: @org, manager: @manager)
    end

    test "creates campaign, alert, and repository records" do
      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        assert_changes -> { SecurityCampaigns::SecurityCampaignRepository.count }, from: 0, to: 2 do
          assert_changes -> { SecurityCampaigns::SecurityCampaignAlert.count }, from: 0, to: 3 do
            CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
          end
        end
      end
    end

    test "instruments to notifications" do
      GlobalInstrumenter.expects(:instrument).with("security_campaigns.security_campaign_create", anything).once
      GlobalInstrumenter.expects(:instrument).with("security_campaigns.security_campaign_repository_notification", anything).once

      CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
    end

    test "publishes a telemetry hydro event" do
      @logical_alert_info = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
        @repo2.id => [Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 3, tool: { name: "CodeQL" })]
      }
      campaign = CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@current_user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        query: @query_string,
        repo_count: 2,
        alert_count: 4,
        organization: Hydro::EntitySerializer.organization(@org),
        manager: Hydro::EntitySerializer.user(@manager),
        description: @campaign.description,
        security_campaign: {
          id: campaign.id,
          number: campaign.number,
          name: campaign.name,
          organization_id: campaign.organization_id,
          manager_id: campaign.manager_id,
          due_date: campaign.ends_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at,
          closed_at: campaign.closed_at,
        }
      }, schema: "github.security_campaigns.v0.SecurityCampaignCreate")
    end

    test "skips duplicate records gracefully" do
      @logical_alert_info[@repo1.id] += [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" })]
      @logical_alert_info[@repo1.id] += [Turboscan::Proto::Result.new(number: 4, tool: { name: "CodeQL" })]

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, from: 0, to: 1 do
        assert_changes -> { SecurityCampaigns::SecurityCampaignRepository.count }, from: 0, to: 2 do
          assert_changes -> { SecurityCampaigns::SecurityCampaignAlert.count }, from: 0, to: 4 do
            CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
          end
        end
      end
    end

    test "raises an error if the organization has too many campaigns" do
      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        (SecurityCampaigns::MAX_CAMPAIGNS_COUNT + 1).times do
          campaign = build(:security_campaign, organization: @org, manager: @manager)
          CreationService.call(campaign:, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
        end
      end
      assert_equal MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "raises an error if the open campaigns limit is reached" do
      (SecurityCampaigns::MAX_CAMPAIGNS_COUNT).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      exception = assert_raises(ActiveRecord::RecordNotSaved) do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
      assert_equal MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE, exception.message
    end

    test "does not rate limit when feature flag is disabled" do
      enable_content_creation_rate_limiting

      Timecop.freeze do
        10.times do
          campaign = build(:security_campaign, organization: @org, manager: @manager)
          campaign.check_creation_rate_limit
        end

        campaign = build(:security_campaign, organization: @org, manager: @manager)
        CreationService.call(campaign:, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
        assert campaign.persisted?
      end
    end

    test "raises an error if the rate limit is exceeded" do
      enable_content_creation_rate_limiting

      GitHub.flipper[:security_campaigns_rate_limited_creation].enable(@org)

      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]

      Timecop.freeze do
        10.times do
          campaign = build(:security_campaign, organization: @org, manager: @manager)
          campaign.check_creation_rate_limit
        end

        campaign = build(:security_campaign, organization: @org, manager: @manager)
        assert_raises(ActiveRecord::RecordInvalid, expected_errors) do
          CreationService.call(campaign:, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
        end

        assert_equal expected_errors, campaign.errors.full_messages
      end

      assert_dogstats_increment(
        "rate_limited_creation",
        tags: ["subject:security_campaigns/security_campaign", "name:per_user_minute", "config_type:dynamic", "skip_increment:false"]
      )
    end

    test "does not check closed campaigns for campaigns limit" do
      (SecurityCampaigns::MAX_CAMPAIGNS_COUNT - 1).times do
        create(:security_campaign, organization: @org)
      end

      create(:security_campaign, organization: @org, closed_at: Time.now)

      assert_changes -> { SecurityCampaigns::SecurityCampaign.count }, 1 do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
    end

    test "enqueues autofix job" do
      @logical_alert_info = {
        @repo1.id => [Turboscan::Proto::Result.new(number: 1, tool: { name: "CodeQL" }), Turboscan::Proto::Result.new(number: 2, tool: { name: "CodeQL" })],
      }

      assert_enqueued_jobs(1, only: SecurityCampaigns::GenerateAutofixesJob) do
        assert_enqueued_with(job: SecurityCampaigns::GenerateAutofixesJob, args: proc {
          |args| args[0][:logical_alert_info] == [{ repo_id: @repo1.id, alerts: [{ alert_number: 1, tool_name: "CodeQL" }, { alert_number: 2, tool_name: "CodeQL" }] }]
        }) do
          CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
        end
      end
    end

    test "does not insert SecurityCampaignRepository when one_email_per_campaign is enabled" do
      GitHub.flipper[:security_campaigns_one_email_per_campaign].enable

      assert_no_changes -> { SecurityCampaigns::SecurityCampaignRepository.count } do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
    end

    test "does not instrument to notifications when one_email_per_campaign is enabled" do
      GitHub.flipper[:security_campaigns_one_email_per_campaign].enable

      GlobalInstrumenter.expects(:instrument).with("security_campaigns.security_campaign_create", anything).once
      GlobalInstrumenter.expects(:instrument).with("security_campaigns.security_campaign_repository_notification", anything).never

      CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
    end

    test "enqueues a job to create SecurityCampaignUser records when one_email_per_campaign is enabled" do
      GitHub.flipper[:security_campaigns_one_email_per_campaign].enable

      assert_enqueued_jobs 1, only: SendCreationNotificationJob do
        CreationService.call(campaign: @campaign, logical_alert_info: @logical_alert_info, actor: @current_user, query_string: @query_string)
      end
    end
  end
end
