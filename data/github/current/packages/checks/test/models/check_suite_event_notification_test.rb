# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuiteEventNotificationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "deliver?" do
    test "returns true if user wants to be notified of all results" do
      check_suite = create(:check_suite, :success)
      notification = CheckSuiteEventNotification.new(check_suite)
      settings = Newsies::Settings.new(@user.id)
      settings.continuous_integration_failures_only = false
      assert notification.deliver?(settings)
    end

    test "returns true if user wants to be notified of failures only and the check suite failed" do
      check_suite = create(:check_suite, :failure)
      notification = CheckSuiteEventNotification.new(check_suite)
      settings = Newsies::Settings.new(@user.id)
      settings.continuous_integration_failures_only = true

      assert notification.deliver?(settings)
    end

    test "returns false if user wants failures only but the check suite did not fail" do
      check_suite = create(:check_suite, :success)
      notification = CheckSuiteEventNotification.new(check_suite)
      settings = Newsies::Settings.new(@user.id)
      settings.continuous_integration_failures_only = true

      refute notification.deliver?(settings)
    end

    test "returns false if if user wants to be notified of all results and check suite is in action_required state" do
      check_suite = create(:check_suite, conclusion: :action_required)

      notification = CheckSuiteEventNotification.new(check_suite)
      settings = Newsies::Settings.new(@user.id)
      settings.continuous_integration_failures_only = false

      refute notification.deliver?(settings)
    end

    test "returns false if user wants failures only and check suite is in action_required state" do
      check_suite = create(:check_suite, conclusion: :action_required)

      notification = CheckSuiteEventNotification.new(check_suite)
      settings = Newsies::Settings.new(@user.id)
      settings.continuous_integration_failures_only = true

      refute notification.deliver?(settings)
    end
  end
end
