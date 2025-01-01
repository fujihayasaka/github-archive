# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotFreeUserCheckJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  # include GitHub::LoggerHelper

  test "doesn't call command with flag disabled" do
    Copilot::FreeUserProcessorJob.expects(:perform_later).never
    logs = capture_logs do
      Copilot::FreeUserCheckJob.perform_now
    end

    assert_match "Skipping Copilot::FreeUserCheckJob", logs
  end

  test "calls when the flag is enabled and no free users to check" do
    GitHub.flipper[:copilot_free_user_check_job].enable
    GitHub.flipper[:copilot_chatterbox].enable
    Copilot::FreeUserProcessorJob.expects(:perform_later).never
    GitHub::Chatterbox.client.expects(:say!).at_least_once
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Starting Copilot::FreeUserCheckJob").once

    output = capture_logs do
      Copilot::FreeUserCheckJob.perform_now
    end

    assert output.include?("Finished Copilot free user check job")
  end

  test "calls when the flag is enabled and some free users to check" do
    GitHub.flipper[:copilot_free_user_check_job].enable

    # unsubscribed free user, should be cleaned up
    unsubscribed = create(
      :copilot_free_user,
      :educational,
      user: create(:user),
      last_checked_date: Date.today - 2.years,
      subscribed: false,
      subscribed_at: nil,
      created_at: Time.now.utc - 2.years,
    )

    # subscribed free user, should be updated
    old_date = Date.today - 2.years
    free_user = create(
      :copilot_free_user,
      :educational,
      user: create(:user),
      last_checked_date: old_date,
      subscribed: true,
      subscribed_at: Time.now.utc,
    )

    Copilot::FreeUserProcessorJob.expects(:perform_later).with(free_user.id).once
    output = capture_logs do
      Copilot::FreeUserCheckJob.perform_now
    end
    assert_match "Performing Copilot::FreeUserCheckJob", output

    assert output.include?("gh.copilot.free_user.unsubscribed.count=\"1\"")
    assert output.include?("gh.copilot.free_user.to_update.count=\"1\"")
    assert output.include?("Updating free users")
    assert output.include?("Deleting unsubscribed free users")

    refute Copilot::FreeUser.exists?(unsubscribed.id)
    assert Copilot::FreeUser.exists?(free_user.id)
  end

  test "calls when the flag is enabled and users need " do
    GitHub.flipper[:copilot_free_user_check_job].enable

    # unsubscribed free user, should be cleaned up
    unsubscribed = create(
      :copilot_free_user,
      :educational,
      user: create(:user),
      last_checked_date: Date.today - 2.years,
      subscribed: false,
      subscribed_at: nil,
      created_at: Time.now.utc - 2.years,
    )

    # subscribed free user, should be updated
    old_date = Date.today - 2.years
    free_user = create(
      :copilot_free_user,
      :educational,
      user: create(:user),
      last_checked_date: old_date,
      subscribed: true,
      subscribed_at: Time.now.utc,
    )

    # unlimited free access
    unlimited = create(
      :copilot_free_user,
      :complimentary,
      user: create(:user),
      last_checked_date: Date.new(9999, 12, 31),
      subscribed: true,
      subscribed_at: Date.today,
    )

    perform_enqueued_jobs(only: Copilot::FreeUserProcessorJob) do
      output = capture_logs do
        Copilot::FreeUserCheckJob.perform_now
      end

      assert output.include?("gh.copilot.free_user.unsubscribed.count=\"1\"")
      assert output.include?("gh.copilot.free_user.to_update.count=\"1\"")
      assert output.include?("Updating free users")
      assert output.include?("Deleting unsubscribed free users")

      refute Copilot::FreeUser.exists?(unsubscribed.id)
      assert Copilot::FreeUser.exists?(free_user.id)
      assert Copilot::FreeUser.exists?(unlimited.id)

      assert_equal Date.new(9999, 12, 31), Copilot::FreeUser.find(unlimited.id).last_checked_date

      refute_equal old_date, Copilot::FreeUser.find(free_user.id).last_checked_date
    end
  end
end if GitHub.copilot_enabled?
