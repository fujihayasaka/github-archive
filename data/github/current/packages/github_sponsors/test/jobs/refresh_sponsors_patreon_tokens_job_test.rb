# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RefreshSponsorsPatreonTokensJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @spu = create(:sponsors_patreon_user,
      patreon_access_token: "old-access-token",
      patreon_refresh_token: "old-refresh-token",
    )
  end

  if GitHub.sponsors_enabled?
    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: RefreshSponsorsPatreonTokensJob, args: [@spu]
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: RefreshSponsorsPatreonTokensJob, args: [@spu]
    end

    test "updates the access and refresh tokens on the given SponsorsPatreonUser" do
      @spu.update!(patreon_refresh_token: "my_refresh_token") # see VCR cassette
      freeze_time
      expires_in = 2678400 # see VCR cassette
      expected_refresh_at = Time.now + expires_in - SponsorsPatreonUser::TOKEN_EXPIRY_GRACE_PERIOD_IN_DAYS.days

      assert_enqueued_with(
        job: RefreshSponsorsPatreonTokensJob,
        args: [@spu],
        at: expected_refresh_at,
      ) do
        VCR.use_cassette("patreon/refresh_token") do
          RefreshSponsorsPatreonTokensJob.perform_now(@spu)
        end
      end

      assert_equal "lovely-new-access-token", @spu.reload.patreon_access_token
      assert_equal "fancy-new-refresh-token", @spu.patreon_refresh_token
    end

    test "deletes the SponsorsPatreonUser when Patreon responds with a 401 Unauthorized" do
      @spu.update!(patreon_refresh_token: "bad_refresh_token") # see VCR cassette

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        assert_difference(-> { SponsorsPatreonUser.count }, -1) do
          SyncSponsorsPatreonWebhooks.stub_const(:RECEIVING_URL, "https://www.github.localhost.com/sponsors/patreon_webhook") do
            VCR.use_cassette("patreon/delete_webhook") do
              VCR.use_cassette("patreon/get_webhooks_one_result") do
                VCR.use_cassette("patreon/refresh_token_401") do
                  RefreshSponsorsPatreonTokensJob.perform_now(@spu)
                end
              end
            end
          end
        end
      end

      refute SponsorsPatreonUser.exists?(@spu.id)
    end

    test "retries when Patreon responds with a non-401 error" do
      assert_retry_on_error SponsorsPatreonClient::Error, RefreshSponsorsPatreonTokensJob, [@spu]
    end

    test "no-op when no refresh token is present" do
      @spu.update!(patreon_refresh_token: "")

      SponsorsPatreonClient.expects(:refresh_token).never

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        RefreshSponsorsPatreonTokensJob.perform_now(@spu)
      end

      assert_equal "old-access-token", @spu.reload.patreon_access_token
      assert_equal "", @spu.patreon_refresh_token
    end
  else
    test "no-op when Sponsors is not a feature" do
      SponsorsPatreonClient.expects(:refresh_token).never

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        RefreshSponsorsPatreonTokensJob.perform_now(@spu)
      end

      assert_equal "old-access-token", @spu.reload.patreon_access_token
      assert_equal "old-refresh-token", @spu.patreon_refresh_token
    end
  end
end
