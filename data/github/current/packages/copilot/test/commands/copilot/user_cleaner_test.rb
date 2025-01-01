# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::UserCleanerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper

  context "perform" do
    # users either need to be deleted or spammy to be cleaned up
    test "it does nothing for a cool user" do
      user = create(:user)
      Copilot::ErrorReporter.expects(:report!).with(
        Copilot::Errors::UserCannotBeCleanedError.new("User cannot be cleaned"),
        extra_details: { "gh.user.id" => user.id },
      )
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
      end
      assert_includes logs, "User cannot be cleaned"
    end

    context "spammy" do
      test "it cleans up configuration" do
        Copilot::ErrorReporter.expects(:report!).never
        config = create(:copilot_configuration, :user)
        user = config.configurable
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Configuration.exists?(configurable_type: "User", configurable_id: user.id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        assignment = create(:copilot_seat_assignment, :user)
        user = assignment.assignable
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::SeatAssignment.exists?(assignable_type: "User", assignable_id: user.id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        user = seat.assigned_user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Seat.exists?(assigned_user_id: user.id)
      end

      test "it cleans up free users" do
        Copilot::ErrorReporter.expects(:report!).never
        free_user = create(:copilot_free_user)
        user = free_user.user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::FreeUser.exists?(user_id: user.id)
      end

      test "it cleans up limited users" do
        Copilot::ErrorReporter.expects(:report!).never
        limited_user = create(:copilot_limited_user)
        user = limited_user.user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::LimitedUser.exists?(user_id: user.id)
      end

      test "it cleans up editor notifications" do
        Copilot::ErrorReporter.expects(:report!).never
        notification = create(:copilot_editor_notification)
        user = notification.user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::EditorNotification.exists?(user_id: user.id)
      end

      test "it cleans up aggregate usage details" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_aggregate_usage_detail)
        user = detail.user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::AggregateUsageDetail.exists?(user_id: user.id)
      end

      test "it cleans up activities" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_activity)
        user = detail.seat.assigned_user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Activity.exists?(copilot_seat_id: detail.copilot_seat_id)
      end

      test "it cleans up activity_histories" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_activity_history)
        user = detail.seat.assigned_user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::ActivityHistory.exists?(copilot_seat_id: detail.copilot_seat_id)
      end

      test "it cleans up authentications" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_authentication)
        user = detail.seat.assigned_user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Authentication.exists?(copilot_seat_id: detail.copilot_seat_id)
      end

      test "it cleans up authentication histories" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_authentication_history)
        user = detail.seat.assigned_user
        user.update(spammy: true)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::AuthenticationHistory.exists?(copilot_seat_id: detail.copilot_seat_id)
      end
    end

    context "deleted" do
      test "it cleans up configuration" do
        Copilot::ErrorReporter.expects(:report!).never
        config = create(:copilot_configuration, :user)
        user = config.configurable
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Configuration.exists?(configurable_type: "User", configurable_id: user.id)
      end

      test "it cleans up seat assignments" do
        Copilot::ErrorReporter.expects(:report!).never
        assignment = create(:copilot_seat_assignment, :user)
        user = assignment.assignable
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::SeatAssignment.exists?(assignable_type: "User", assignable_id: user.id)
      end

      test "it cleans up seats" do
        Copilot::ErrorReporter.expects(:report!).never
        seat = create(:copilot_seat)
        user = seat.assigned_user
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::Seat.exists?(assigned_user_id: user.id)
      end

      test "it cleans up free users" do
        Copilot::ErrorReporter.expects(:report!).never
        free_user = create(:copilot_free_user)
        user = free_user.user
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::FreeUser.exists?(user_id: user.id)
      end

      test "it cleans up editor notifications" do
        Copilot::ErrorReporter.expects(:report!).never
        notification = create(:copilot_editor_notification)
        user = notification.user
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::EditorNotification.exists?(user_id: user.id)
      end

      test "it cleans up aggregate usage details" do
        Copilot::ErrorReporter.expects(:report!).never
        detail = create(:copilot_aggregate_usage_detail)
        user = detail.user
        user.destroy
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::UserCleaner.call(user.id)
        end
        refute Copilot::AggregateUsageDetail.exists?(user_id: user.id)
      end
    end
  end
end if GitHub.copilot_enabled?
