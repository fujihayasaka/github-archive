# typed: true
# frozen_string_literal: true

require "test_helper"

class SyncSponsorsPatreonWebhooksTest < GitHub::TestCase
  fixtures do
    @spu = create(:sponsors_patreon_user)
    @patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
      campaign_id: "10439677") # see get_webhooks_one_result VCR cassette
  end

  if GitHub.sponsors_enabled?
    test "deletes and recreates Patreon webhooks in Patreon" do
      old_webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu, webhook_id: "722598",
        campaign_id: @patreon_tier.campaign_id)

      new_webhooks = VCR.use_cassette("patreon/create_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: @spu)
        end
      end

      assert_equal 1, new_webhooks.size
      refute SponsorsPatreonCampaignWebhook.exists?(old_webhook.id), "should have deleted our webhook record"
      new_webhook = new_webhooks.first
      assert_equal @spu, new_webhook.sponsors_patreon_user
      assert_equal "722601", new_webhook.webhook_id # see create_webhook VCR cassette
    end

    test "creates webhook on Patreon if SponsorsPatreonUser has a Patreon campaign" do
      assert_equal 1, @spu.patreon_campaign_ids.size, "need a SponsorsPatreonUser with a single campaign"

      webhooks = assert_difference("SponsorsPatreonCampaignWebhook.count") do
        VCR.use_cassette("patreon/create_webhook") do
          VCR.use_cassette("patreon/delete_webhook") do
            VCR.use_cassette("patreon/get_webhooks_one_result") do
              SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: @spu)
            end
          end
        end
      end

      assert_equal 1, webhooks.size
      webhook = webhooks.first
      refute_nil webhook
      assert_equal @spu, webhook.sponsors_patreon_user
      assert_equal @patreon_tier.campaign_id, webhook.campaign_id

      # See create_webhook VCR cassette:
      assert_equal "722601", webhook.webhook_id
      assert_equal "-M_E903yBm7Sih2dkq3EbIDcVfFxLq8P6ePA7sRXMWEJYg9A1fb_gtQ4VkPmQLnA", webhook.secret
    end

    test "creates a webhook on Patreon for each campaign when a maintainer has more than one" do
      expected_triggers = ["members:create", "members:update", "members:delete", "members:pledge:create",
        "members:pledge:update", "members:pledge:delete"]
      campaign_id1 = @patreon_tier.campaign_id
      campaign_id2 = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu).campaign_id

      # For webhook creation:
      SponsorsPatreonClient.any_instance.expects(:create_webhook).once
        .with(campaign_id: campaign_id1, uri: SyncSponsorsPatreonWebhooks::RECEIVING_URL, triggers: expected_triggers)
        .returns("data" => { "id" => "123", "type" => "webhook", "attributes" => { "secret" => "foo",
          "triggers" => expected_triggers } })
      SponsorsPatreonClient.any_instance.expects(:create_webhook).once
        .with(campaign_id: campaign_id2, uri: SyncSponsorsPatreonWebhooks::RECEIVING_URL, triggers: expected_triggers)
        .returns("data" => { "id" => "456", "type" => "webhook", "attributes" => { "secret" => "bar",
          "triggers" => expected_triggers } })

      # For webhook deletion:
      SponsorsPatreonClient.any_instance.expects(:get_webhooks).once.returns("data" => [])

      assert_difference("SponsorsPatreonCampaignWebhook.count", 2) do
        SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: @spu)
      end

      webhook1 = @spu.sponsors_patreon_campaign_webhooks.for_campaign_id(campaign_id1).first
      refute_nil webhook1
      assert_equal "123", webhook1.webhook_id
      assert_equal "foo", webhook1.secret
      assert_equal expected_triggers, webhook1.triggers
      webhook2 = @spu.sponsors_patreon_campaign_webhooks.for_campaign_id(campaign_id2).first
      refute_nil webhook2
      assert_equal "456", webhook2.webhook_id
      assert_equal "bar", webhook2.secret
      assert_equal expected_triggers, webhook2.triggers
    end

    test "raises UnprocessableError if any webhook fails to create" do
      error_message = "Could not create webhook for SponsorsPatreonUser #{@spu.id} for campaign " \
        "#{@patreon_tier.campaign_id}: 400 error: Invalid parameter for 'campaign': resource is missing."

      VCR.use_cassette("patreon/create_webhook_for_inexistent_campaign") do
        VCR.use_cassette("patreon/delete_webhook") do
          VCR.use_cassette("patreon/get_webhooks_one_result") do
            assert_raises_with_message(SyncSponsorsPatreonWebhooks::UnprocessableError, error_message) do
              SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: @spu)
            end
          end
        end
      end
    end

    test "raises UnprocessableError if patreon_client is missing" do
      spu = create(:sponsors_patreon_user, patreon_access_token: nil, patreon_refresh_token: nil)

      assert_raises_with_message(SyncSponsorsPatreonWebhooks::UnprocessableError,
        "Can't authenticate with Patreon API for given account") do
        SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: spu)
      end
    end

    test "raises UnprocessableError there are no Patreon campaign IDs" do
      spu = create(:sponsors_patreon_user, :sponsor)
      assert_empty spu.patreon_campaign_ids, "need a SponsorsPatreonUser with no campaign IDs"

      assert_raises_with_message(SyncSponsorsPatreonWebhooks::UnprocessableError, "A Patreon campaign is missing") do
        SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: spu)
      end
    end
  else
    test "raises if GitHub Sponsors is disabled" do
      assert_raises_with_message(SyncSponsorsPatreonWebhooks::UnprocessableError, "GitHub Sponsors is not enabled") do
        SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: @spu)
      end
    end
  end
end
