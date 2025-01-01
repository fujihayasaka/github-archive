# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUserSettingsStandaloneEMU < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
  end

  setup do
    @seat_assignment.convert_to_seats
  end

  context "IDE chat" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_chat!

      user = @seat_assignment.seats.first.assigned_user
      copilot_user = Copilot::User.new(user)

      assert copilot_user.chat_enabled?
      refute copilot_user.chat_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_chat!

      user = @seat_assignment.seats.first.assigned_user
      copilot_user = Copilot::User.new(user)

      assert copilot_user.chat_disabled?
      refute copilot_user.chat_enabled?
    end
  end

  context "cli" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@standalone_enterprise).cli_enabled!

      @user.reload

      assert Copilot::User.new(@user).cli_enabled?
      refute Copilot::User.new(@user).cli_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@standalone_enterprise).cli_disabled!

      @user.reload

      assert Copilot::User.new(@user).cli_disabled?
      refute Copilot::User.new(@user).cli_enabled?
    end
  end

  context "mobile chat" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@standalone_enterprise).enable_mobile_chat!

      @user.reload

      assert Copilot::User.new(@user).mobile_chat_enabled?
      refute Copilot::User.new(@user).mobile_chat_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@standalone_enterprise).disable_mobile_chat!

      @user.reload

      assert Copilot::User.new(@user).mobile_chat_disabled?
      refute Copilot::User.new(@user).mobile_chat_enabled?
    end
  end
end if TestEnv.test_with_all_emus? && GitHub.copilot_enabled?
