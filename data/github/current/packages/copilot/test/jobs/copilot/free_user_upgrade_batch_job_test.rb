# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class FreeUserUpgradeBatchJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper
  include GitHub::LoggerHelper

  context "upgrades Free users to Complimentary Pro when eligible" do
    test "subscribes eligible user to comp pro and destroys limited user" do
      enable_feature_flag(:free_user_upgrade_job)
      disable_feature_flag(:free_user_upgrade_job_noop)
      user = create(:user)
      create(:copilot_limited_user, user: user)
      free_user = create(:copilot_free_user, user: user)
      og_copilot_user = Copilot::User.new(user)
      limited_user = T.must(Copilot::LimitedUser.find_by(user_id: user.id))

      assert_equal false, free_user.subscribed?
      assert_equal :FREE_LIMITED_COPILOT, og_copilot_user.access_type

      first_id, last_id = call_parent_job_and_get_batch_ids

      logs = capture_logs do
        Copilot::FreeUserUpgradeBatchJob.perform_now(first_id, last_id)
      end

      user.reload
      free_user.reload
      copilot_user = Copilot::User.new(user)

      assert free_user.subscribed?
      assert_raises(ActiveRecord::RecordNotFound) { limited_user.reload }
      assert_includes logs, "Starting FreeUserUpgradeBatchJob"
      assert_includes logs, "Upgrading Copilot Free user to Copilot Complimentary Pro because they are eligible"
      assert_includes logs, "gh.copilot.access_type=\"#{og_copilot_user.access_type}\""
      assert_includes logs, "gh.copilot.free_user_type=\"#{free_user.free_user_type}\""
      assert_equal :FREE_EDUCATIONAL, copilot_user.access_type
    end

    test "subscribes eligible user without existing free user to comp pro and destroys limited user" do
      enable_feature_flag(:free_user_upgrade_job)
      disable_feature_flag(:free_user_upgrade_job_noop)
      User.any_instance.stubs(:github_star?).returns(true)
      Copilot::User.any_instance.stubs(:github_star?).returns(true)
      user = create(:user)
      create(:copilot_limited_user, user: user)
      og_copilot_user = Copilot::User.new(user)
      limited_user = T.must(Copilot::LimitedUser.find_by(user_id: user.id))

      assert_equal :FREE_LIMITED_COPILOT, og_copilot_user.access_type

      first_id, last_id = call_parent_job_and_get_batch_ids

      logs = capture_logs do
        Copilot::FreeUserUpgradeBatchJob.perform_now(first_id, last_id)
      end

      user.reload
      copilot_user = Copilot::User.new(user)
      free_user = T.must(copilot_user.free_user)

      assert free_user.subscribed?
      assert_raises(ActiveRecord::RecordNotFound) { limited_user.reload }
      assert_includes logs, "Starting FreeUserUpgradeBatchJob"
      assert_includes logs, "Upgrading Copilot Free user to Copilot Complimentary Pro because they are eligible"
      assert_includes logs, "gh.copilot.access_type=\"#{og_copilot_user.access_type}\""
      assert_includes logs, "gh.copilot.free_user_type=\"#{free_user.free_user_type}\""
      assert_equal :FREE_GITHUB_STAR, copilot_user.access_type
    end

    test "does not process non-eligible or subscribed Comp Pro users" do
      enable_feature_flag(:free_user_upgrade_job)
      disable_feature_flag(:free_user_upgrade_job_noop)
      limited_user = create(:copilot_limited_user)
      create(:copilot_free_user, subscribed: true)

      first_id, last_id = call_parent_job_and_get_batch_ids

      logs = capture_logs do
        Copilot::FreeUserUpgradeBatchJob.perform_now(first_id, last_id)
      end

      refute_nil Copilot::LimitedUser.find_by(id: limited_user.id)
      assert_match "Starting FreeUserUpgradeBatchJob", logs
      refute_match "Upgrading Copilot Free user to Copilot Complimentary Pro because they are eligible", logs
    end

    test "does nothing when feature flag is disabled" do
      disable_feature_flag(:free_user_upgrade_job)
      disable_feature_flag(:free_user_upgrade_job_noop)
      logs = capture_logs do
        Copilot::FreeUserUpgradeBatchJob.perform_now(0, 0)
      end

      refute_match "Starting FreeUserUpgradeBatchJob", logs
    end

    test "does not run write ops when noop flag is enabled" do
      disable_feature_flag(:free_user_upgrade_job)
      enable_feature_flag(:free_user_upgrade_job_noop)
      user = create(:user)
      create(:copilot_limited_user, user: user)
      free_user = create(:copilot_free_user, user: user)
      copilot_user = Copilot::User.new(user)
      limited_user = T.must(Copilot::LimitedUser.find_by(user_id: user.id))

      assert_equal false, free_user.subscribed?
      assert_equal :FREE_LIMITED_COPILOT, copilot_user.access_type

      first_id, last_id = call_parent_job_and_get_batch_ids

      logs = capture_logs do
        Copilot::FreeUserUpgradeBatchJob.perform_now(first_id, last_id)
      end

      user.reload
      free_user.reload
      copilot_user = Copilot::User.new(user)

      refute_nil Copilot::LimitedUser.find_by(id: limited_user.id)
      assert_includes logs, "Starting FreeUserUpgradeBatchJob"
      assert_includes logs, "Upgrading Copilot Free user to Copilot Complimentary Pro because they are eligible"
      assert_includes logs, "gh.copilot.access_type=\"#{copilot_user.access_type}\""
      assert_includes logs, "gh.copilot.free_user_type=\"#{free_user.free_user_type}\""
      assert_includes logs, "gh.copilot.free_signup_reason=\"#{copilot_user.free_signup_reason}\""
      assert_equal false, free_user.subscribed?
      assert_equal :FREE_LIMITED_COPILOT, copilot_user.access_type
    end
  end

  private

  sig { returns([Integer, Integer]) }
  def call_parent_job_and_get_batch_ids
    logs = capture_logs do
      Copilot::FreeUserUpgradeJob.perform_now
    end

    first_seat_id = logs.match(/gh\.copilot\.batch_first_seat_id="(\d+)"/)[1]
    last_seat_id = logs.match(/gh\.copilot\.batch_last_seat_id="(\d+)"/)[1]

    [first_seat_id.to_i, last_seat_id.to_i]
  end
end
