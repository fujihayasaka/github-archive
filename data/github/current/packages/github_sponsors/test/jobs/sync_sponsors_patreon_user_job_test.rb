# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncSponsorsPatreonUserJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @spu = create(:sponsors_patreon_user, :with_tier)
  end

  setup do
    @fake_receiving_url = "https://www.github.localhost.com/sponsors/patreon_webhook"
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SyncSponsorsPatreonUserJob, args: [@spu]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncSponsorsPatreonUserJob, args: [@spu]
  end

  test "calls the user and webhooks sync" do
    actor = @spu.user

    # Full test coverage for the callees is in their respective test files
    SyncSponsorsPatreonUser.expects(:call).once.with(sponsors_patreon_user: @spu)
    SyncSponsorsPatreonWebhooks.expects(:call).once.with(sponsors_patreon_user: @spu)

    SyncSponsorsPatreonWebhooks.stub_const(:RECEIVING_URL, @fake_receiving_url) do
      VCR.use_cassette("patreon/get_webhooks_empty") do
        SyncSponsorsPatreonUserJob.perform_now(@spu, actor: actor)
      end
    end
  end

  test "does not call sync webhooks if SponsorsPatreonUser is already subscribed to webhooks" do
    @spu.patreon_campaign_ids.each do |campaign_id|
      create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu, campaign_id: campaign_id)
    end

    SyncSponsorsPatreonUser.expects(:call).once.with(sponsors_patreon_user: @spu)
    SyncSponsorsPatreonWebhooks.expects(:call).never

    SyncSponsorsPatreonWebhooks.stub_const(:RECEIVING_URL, @fake_receiving_url) do
      VCR.use_cassette("patreon/get_webhooks_one_result") do
        SyncSponsorsPatreonUserJob.perform_now(@spu)
      end
    end
  end
end
