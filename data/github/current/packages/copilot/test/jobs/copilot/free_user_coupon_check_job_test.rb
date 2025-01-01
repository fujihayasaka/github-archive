# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotFreeUserCouponCheckJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  # include GitHub::LoggerHelper

  context "no param passed" do
    test "doesn't call command with flag disabled" do
      Copilot::FreeUserCouponCheckJob.expects(:perform_later).never
      logs = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now
      end

      assert_match "Skipping Copilot::FreeUserCouponCheckJob", logs
    end

    test "calls when the flag is enabled and no free users to check" do
      GitHub.flipper[:copilot_free_user_coupon_check_job].enable

      Copilot::FreeUserCouponCheckJob.expects(:perform_later).never
      output = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now
      end

      assert output.include?("Starting FreeUserCouponCheckJob")
    end

    test "calls when the flag is enabled and some free users to check" do
      GitHub.flipper[:copilot_free_user_coupon_check_job].enable

      # engaged oss user, should NOT queue background job
      create(
        :copilot_free_user,
        :engaged_oss,
        user: create(:user),
        last_checked_date: Date.current,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      # educational user, should queue background job
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.current,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      # educational user, should queue background job
      workshop_free_user = create(
        :copilot_free_user,
        :workshop,
        user: create(:user),
        last_checked_date: Date.current,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      Copilot::FreeUserCouponCheckJob.expects(:perform_later).with(free_user_id: free_user.id).once
      Copilot::FreeUserCouponCheckJob.expects(:perform_later).with(free_user_id: workshop_free_user.id).once
      output = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now
      end
      assert_match "Performing Copilot::FreeUserCouponCheckJob", output

      assert output.include?("gh.copilot.free_user.educational.count=\"1\"")
      assert output.include?("gh.copilot.free_user.workshop.count=\"1\"")
      assert output.include?("Checking coupons for educational users")
      assert output.include?("Checking coupons for workshop users")

      assert Copilot::FreeUser.exists?(free_user.id)
    end
  end

  context "param passed" do
    test "doesn't do anything for a free user that doesn't exist" do
      GitHub.flipper[:copilot_free_user_coupon_check_job].enable

      Copilot::FreeUserCouponCheckJob.any_instance.expects(:handle_copilot_error).with(Copilot::Errors::FreeUserError.new("No free user found")).once
      output = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: (Copilot::FreeUser.last&.id || 0) + 1)
      end
      assert_match "Starting FreeUserCouponCheckJob", output
    end

    test "doesn't do anything for a user that doesn't exist" do
      GitHub.flipper[:copilot_free_user_coupon_check_job].enable

      user = create(:user)

      free_user = create(
        :copilot_free_user,
        :educational,
        user: user,
        last_checked_date: Date.current,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      user.destroy

      Copilot::FreeUserCouponCheckJob.any_instance.expects(:handle_copilot_error).with(Copilot::Errors::FreeUserError.new("No user found")).once
      output = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
      end
      assert_match "Starting FreeUserCouponCheckJob", output
    end

    test "doesn't do anything for engaged oss users" do
      GitHub.flipper[:copilot_free_user_coupon_check_job].enable

      # educational user, should queue background job
      free_user = create(
        :copilot_free_user,
        :engaged_oss,
        user: create(:user),
        last_checked_date: Date.current,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      output = capture_logs do
        Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
      end
      assert_match "Performing Copilot::FreeUserCouponCheckJob", output
      assert_match "Expected Educational/Faculty/Workshop Free User Typ", output
      assert Copilot::FreeUser.exists?(free_user.id)
    end

    context "educational user" do
      test "doesn't remove an educational user whose coupon is chill" do
        GitHub.flipper[:copilot_free_user_coupon_check_job].enable

        free_user = create(
          :copilot_free_user,
          :educational_redeemed,
        )

        output = capture_logs do
          Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
        end
        assert_match "Performing Copilot::FreeUserCouponCheckJob", output

        assert output.include?("Checking coupon state for free user")
        assert output.include?("Free user still has valid coupon")

        assert Copilot::FreeUser.exists?(free_user.id)
      end

      test "removes an educational user whose coupon is not chill" do
        GitHub.flipper[:copilot_free_user_coupon_check_job].enable

        free_user = create(
          :copilot_free_user,
          :educational_redeemed,
        )

        free_user.user.expire_active_coupon

        output = capture_logs do
          Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
        end
        assert_match "Performing Copilot::FreeUserCouponCheckJob", output

        assert output.include?("Checking coupon state for free user")
        assert output.include?("Free user no longer has valid coupon")

        refute Copilot::FreeUser.exists?(free_user.id)
      end
    end

    context "faculty user" do
      test "doesn't remove an faculty user whose coupon is chill" do
        GitHub.flipper[:copilot_free_user_coupon_check_job].enable

        free_user = create(
          :copilot_free_user,
          :faculty_redeemed,
        )

        output = capture_logs do
          Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
        end
        assert_match "Performing Copilot::FreeUserCouponCheckJob", output

        assert output.include?("Checking coupon state for free user")
        assert output.include?("Free user still has valid coupon")

        assert Copilot::FreeUser.exists?(free_user.id)
      end

      test "removes an faculty user whose coupon is not chill" do
        GitHub.flipper[:copilot_free_user_coupon_check_job].enable

        free_user = create(
          :copilot_free_user,
          :faculty_redeemed,
        )

        free_user.user.expire_active_coupon

        output = capture_logs do
          Copilot::FreeUserCouponCheckJob.perform_now(free_user_id: free_user.id)
        end
        assert_match "Performing Copilot::FreeUserCouponCheckJob", output

        assert output.include?("Checking coupon state for free user")
        assert output.include?("Free user no longer has valid coupon")

        refute Copilot::FreeUser.exists?(free_user.id)
      end
    end
  end
end if GitHub.copilot_enabled?
