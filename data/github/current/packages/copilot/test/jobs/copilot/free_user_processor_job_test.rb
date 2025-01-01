# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotFreeUserProcessorJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "flag checks" do
    test "doesn't call command with flag disabled" do
      logs = capture_logs do
        Copilot::FreeUserProcessorJob.perform_now(1)
      end
      assert_match "Skipping Copilot::FreeUserProcessorJob", logs
    end

    test "calls when the flag is enabled and id is invalid" do
      GitHub.flipper[:copilot_free_user_check_job].enable
      output = capture_logs do
        Copilot::FreeUserProcessorJob.perform_now(1)
      end
      assert output.include?("Free user not found")
      assert_match "Performing Copilot::FreeUserProcessorJob", output
    end

    test "does not run when the flag is enabled and unsubscribed free user is passed" do
      GitHub.flipper[:copilot_free_user_check_job].enable
      Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).never

      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 2.years,
      )

      output = capture_logs do
        Copilot::FreeUserProcessorJob.perform_now(free_user.id)
      end
      assert output.include?("Free user not subscribed, deleting record")
      assert_match "Performing Copilot::FreeUserProcessorJob", output
      assert_nil Copilot::FreeUser.find_by(id: free_user.id)
    end

    test "calls when the flag is enabled and free user is passed" do
      GitHub.flipper[:copilot_free_user_check_job].enable
      Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).once

      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 2.years,
        subscribed: true,
        subscribed_at: Time.now.utc,
      )

      output = capture_logs do
        Copilot::FreeUserProcessorJob.perform_now(free_user.id)
      end
      assert output.include?("Processing user")
      assert_match "Performing Copilot::FreeUserProcessorJob", output
    end
  end

  context "process_free_user" do
    test "will not change unlimited complimentary" do
      expected_log_data = {
        "exception.message" => "Future Complimentary Users Cannot Be Updated",
      }
      free_user = create(
        :copilot_free_user,
        :complimentary,
        user: create(:user),
        subscribed: true,
        last_checked_date: Date.new(9999, 12, 31)
      )

      Failbot.expects(:report).with(StandardError.new("Future Complimentary Users Cannot Be Updated"), free_user: free_user)
      assert_logged(**expected_log_data) do
        processor = Copilot::FreeUserProcessorJob.new
        ActiveRecord::Base.connected_to(role: :reading) do
          processor.process_free_user(free_user)
        end
      end
    end

    test "processes complimentary access user who needs to be canceled" do
      free_user = create(
        :copilot_free_user,
        :complimentary,
        user: create(:user),
        subscribed: true,
        last_checked_date: Date.today - 1,
      )
      Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).once

      processor = Copilot::FreeUserProcessorJob.new
      ActiveRecord::Base.connected_to(role: :reading) do
        processor.process_free_user(free_user)
      end
    end

    test "processes technical preview extension who needs to be canceled" do
      free_user = create(
        :copilot_free_user,
        :technical_preview_extension,
        user: create(:user),
        subscribed: true,
        last_checked_date: Date.today - 1.year,
      )
      Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).once

      processor = Copilot::FreeUserProcessorJob.new
      ActiveRecord::Base.connected_to(role: :reading) do
        processor.process_free_user(free_user)
      end
    end

    test "processes y combinator extension who needs to be canceled" do
      free_user = create(
        :copilot_free_user,
        :y_combinator,
        user: create(:user),
        subscribed: true,
        last_checked_date: Date.today - 1.year,
      )
      Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).once

      processor = Copilot::FreeUserProcessorJob.new
      ActiveRecord::Base.connected_to(role: :reading) do
        processor.process_free_user(free_user)
      end
    end

    context "check others that validate free user" do
      [
        [Copilot::FreeUser::EDUCATIONAL, :is_educational_user?],
        [Copilot::FreeUser::ENGAGED_OSS, :is_engaged_oss_user?],
        [Copilot::FreeUser::FACULTY, :is_faculty_user?],
        [Copilot::FreeUser::GITHUB_STAR, :is_github_star_user?],
        [Copilot::FreeUser::MS_MVP, :is_ms_mvp_user?],
        [Copilot::FreeUser::WORKSHOP, :is_workshop_user?],
      ].each do |type, method|
        free_user_type = type.name

        test "cancels #{free_user_type} user who needs to be canceled" do
          free_user = create(
            :copilot_free_user,
            user: create(:user),
            free_user_type: free_user_type,
            subscribed: true,
            last_checked_date: Date.today - 13.months,
          )
          Copilot::FreeUser.stubs(method).returns(false)
          Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).once
          Copilot::FreeUser.any_instance.expects(:refresh!).never

          processor = Copilot::FreeUserProcessorJob.new
          ActiveRecord::Base.connected_to(role: :reading) do
            processor.process_free_user(free_user)
          end
        end

        test "refreshes #{free_user_type} user who doesn't need to be canceled" do
          free_user = create(
            :copilot_free_user,
            user: create(:user),
            free_user_type: free_user_type,
            subscribed: true,
            last_checked_date: Date.today - 13.months,
          )
          Copilot::FreeUser.stubs(method).returns(true)
          Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).never
          Copilot::FreeUser.any_instance.expects(:refresh!).once

          processor = Copilot::FreeUserProcessorJob.new
          ActiveRecord::Base.connected_to(role: :reading) do
            processor.process_free_user(free_user)
          end
        end

        test "does not refresh #{free_user_type} user who doesn't need to be cancelled, but has an org seat assignment" do
          GitHub.flipper[:copilot_free_user_check_job].enable

          free_user = create(
            :copilot_free_user,
            user: create(:user),
            free_user_type: free_user_type,
            subscribed: true,
            last_checked_date: Date.today - 13.months,
          )

          organization = create(:copilot_for_business_enabled_organization)
          organization.add_member(free_user.user)
          create(:copilot_seat, organization: organization, assigned_user: free_user.user)

          Copilot::FreeUser.stubs(method).returns(true)
          Copilot::FreeUser.any_instance.expects(:warn_and_queue_cancel!).never
          Copilot::FreeUser.any_instance.expects(:refresh!).never

          logs = capture_logs do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::FreeUserProcessorJob.perform_now(free_user.id)
            end
          end

          assert_includes(logs, "This user already has a CFB seat")
        end
      end
    end
  end
end if GitHub.copilot_enabled?
