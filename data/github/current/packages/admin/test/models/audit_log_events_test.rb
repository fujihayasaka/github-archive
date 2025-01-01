# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogEventsTest < GitHub::TestCase
  include AuditLogHelpers

  setup do
    # find_audit_events
    @user = create(:user)
    @excluded_user = create(:user)

    with_es_refresh do
      @user.instrument_two_factor_recovery_codes_downloaded
      @excluded_user.instrument_two_factor_recovery_codes_downloaded
    end

    # find_audit_events_for_actions
    @user_for_actions = create(:user)
    with_es_refresh do
      @user_for_actions.instrument_two_factor_recovery_codes_viewed
      @user_for_actions.instrument_two_factor_recovery_codes_printed
      @user_for_actions.instrument_two_factor_recovery_codes_downloaded
    end
  end

  context "#find_audit_events" do
    test "finds audit_events for the user" do
      events = @user.find_audit_events("user.two_factor_recovery_codes_downloaded")

      assert_equal 1, events.length
    end

    test "returns empty array when no results are found" do
      events = @user.find_audit_events("foo")

      assert_equal 0, events.length
    end
  end

  context "#find_audit_events_for_actions" do
    test "finds audit_events matching any of the actions passed" do
      events = @user_for_actions.find_audit_events_for_actions(["user.two_factor_recovery_codes_downloaded", "user.two_factor_recovery_codes_printed"])

      assert_equal 2, events.length
    end

    test "returns empty array when no results are found" do
      events = @user_for_actions.find_audit_events_for_actions(["foo"])

      assert_equal 0, events.length
    end
  end
end
