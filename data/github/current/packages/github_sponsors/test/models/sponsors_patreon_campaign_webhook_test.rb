# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPatreonCampaignWebhookTest < GitHub::TestCase
  context "validations" do
    test "requires campaign_id" do
      webhook = SponsorsPatreonCampaignWebhook.new(campaign_id: "")
      refute_predicate webhook, :valid?
      assert_includes webhook.errors[:campaign_id], "can't be blank"
    end

    test "requires a unique campaign_id per SponsorsPatreonUser" do
      webhook1 = create(:sponsors_patreon_campaign_webhook)
      webhook2 = SponsorsPatreonCampaignWebhook.new(campaign_id: webhook1.campaign_id,
        sponsors_patreon_user_id: webhook1.sponsors_patreon_user_id)
      refute_predicate webhook2, :valid?
      assert_includes webhook2.errors[:campaign_id], "has already been taken"
    end

    test "requires triggers" do
      webhook = SponsorsPatreonCampaignWebhook.new(triggers: [])
      refute_predicate webhook, :valid?
      assert_includes webhook.errors[:triggers], "can't be blank"
    end

    test "requires webhook_id" do
      webhook = SponsorsPatreonCampaignWebhook.new(webhook_id: "")
      refute_predicate webhook, :valid?
      assert_includes webhook.errors[:webhook_id], "can't be blank"
    end

    test "requires a unique webhook_id" do
      webhook1 = create(:sponsors_patreon_campaign_webhook)
      webhook2 = SponsorsPatreonCampaignWebhook.new(webhook_id: webhook1.webhook_id)
      refute_predicate webhook2, :valid?
      assert_includes webhook2.errors[:webhook_id], "has already been taken"
    end

    test "requires secret" do
      webhook = SponsorsPatreonCampaignWebhook.new(secret: "")
      refute_predicate webhook, :valid?
      assert_includes webhook.errors[:secret], "can't be blank"
    end

    test "requires a SponsorsPatreonUser" do
      webhook = SponsorsPatreonCampaignWebhook.new(sponsors_patreon_user: nil)
      refute_predicate webhook, :valid?
      assert_includes webhook.errors[:sponsors_patreon_user], "must exist"
    end
  end

  context "for_campaign_id scope" do
    test "returns webhooks with the specified Patreon campaign ID" do
      webhook1, webhook2 = create_pair(:sponsors_patreon_campaign_webhook)
      refute_equal webhook1.campaign_id, webhook2.campaign_id

      result = SponsorsPatreonCampaignWebhook.for_campaign_id(webhook1.campaign_id)

      assert_includes result, webhook1
      refute_includes result, webhook2
    end
  end

  context "for_webhook_id scope" do
    test "returns webhooks with the specified Patreon webhook ID" do
      webhook1, webhook2 = create_pair(:sponsors_patreon_campaign_webhook)
      refute_equal webhook1.webhook_id, webhook2.webhook_id

      result = SponsorsPatreonCampaignWebhook.for_webhook_id(webhook1.webhook_id)

      assert_includes result, webhook1
      refute_includes result, webhook2
    end
  end

  context "for_patreon_user_id scope" do
    test "returns webhooks for the specified Patreon user ID" do
      spu1, spu2 = create_pair(:sponsors_patreon_user)
      refute_equal spu1.patreon_user_id, spu2.patreon_user_id
      webhook1, webhook2 = create_pair(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu1)
      webhook3, webhook4 = create_pair(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu2)

      result = SponsorsPatreonCampaignWebhook.for_patreon_user_id(spu1.patreon_user_id)

      assert_includes result, webhook1
      assert_includes result, webhook2
      refute_includes result, webhook3
      refute_includes result, webhook4
    end
  end

  test "deletes webhook on Patreon when the record is destroyed" do
    spu = create(:sponsors_patreon_user)
    refute_nil spu.patreon_client, "need a SponsorsPatreonUser that has a Patreon API client"
    webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu,
      webhook_id: "722607") # see VCR cassette

    VCR.use_cassette("patreon/delete_webhook") do
      webhook.destroy!
    end
  end
end
