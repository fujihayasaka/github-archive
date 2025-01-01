# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CleanUpPatreonWebhooksJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @spu = create(:sponsors_patreon_user)
    @webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu,
      webhook_id: "722598") # see get_webhooks_one_result VCR cassette
    create(:patreon_webhook_event, sponsors_patreon_user: @spu, sponsors_patreon_campaign_webhook: @webhook)
  end

  if GitHub.sponsors_enabled?
    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: CleanUpPatreonWebhooksJob, args: [@spu]
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: CleanUpPatreonWebhooksJob, args: [@spu]
    end

    test "retries when Patreon responds with a non-401 error" do
      assert_retry_on_error SponsorsPatreonClient::Error, CleanUpPatreonWebhooksJob, [@spu]
    end

    test "deletes GitHub-related webhooks on Patreon" do
      SponsorsPatreonClient.any_instance.expects(:delete_webhook).once.with("722598")

      SyncSponsorsPatreonWebhooks.stub_const(:RECEIVING_URL, "https://www.github.localhost.com/sponsors/patreon_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          CleanUpPatreonWebhooksJob.perform_now(@spu)
        end
      end
    end

    test "deletes PatreonWebhookEvent records" do
      assert_equal 1, @spu.patreon_webhook_events.count

      VCR.use_cassette("patreon/get_webhooks_one_result") do
        CleanUpPatreonWebhooksJob.perform_now(@spu)
      end

      assert_empty @spu.reload.patreon_webhook_events
    end

    test "deletes SponsorsPatreonCampaignWebhook records" do
      assert_difference("SponsorsPatreonCampaignWebhook.count", -1) do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          CleanUpPatreonWebhooksJob.perform_now(@spu)
        end
      end

      refute SponsorsPatreonCampaignWebhook.exists?(@webhook.id)
    end
  else
    test "no-op when Sponsors is not a feature" do
      SponsorsPatreonClient.expects(:delete_webhook).never

      assert_no_difference("SponsorsPatreonCampaignWebhook.count") do
        CleanUpPatreonWebhooksJob.perform_now(@spu)
      end

      assert_equal 1, @spu.patreon_webhook_events.count
    end
  end
end
