# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUserSettingsStandalone < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @biz = create(:business, :default_managed, seats_plan_type: :basic)
    @user = create(:user)
    @enterprise_team = create(:enterprise_team, business: @biz)
  end

  setup do
    @biz.add_user_accounts([@user.id], business_roles_bitfield: 2)
    @biz.add_owner(@user, actor: @user)
    @enterprise_team.enterprise_team_memberships.create!(user_id: @user.id)
    @seat_assignment = Copilot::SeatAssignment.new(
      id: 1,
      owner_id: @biz.id,
      owner_type: "Business",
      assignable_type: "EnterpriseTeam",
      assignable_id: @enterprise_team.id,
      assigning_user: @user
    )
    @seat_assignment.save!
    @seat_assignment.convert_to_seats
  end

  context "IDE chat" do
    test "enabled if enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.chat_enabled?
      refute copilot_user.chat_disabled?
    end

    test "disabled if enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.chat_disabled?
      refute copilot_user.chat_enabled?
    end
  end

  context "cli" do
    test "enabled if enterprise owning enterprise team enables it" do
      Copilot::Business.new(@seat_assignment.owner).cli_enabled!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.cli_enabled?
      refute copilot_user.cli_disabled?
    end

    test "disabled if enterprise owning enterprise team disables it" do
      Copilot::Business.new(@seat_assignment.owner).cli_disabled!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.cli_disabled?
      refute copilot_user.cli_enabled?
    end
  end

  context "mobile_chat" do
    test "enabled if enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_mobile_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.mobile_chat_enabled?
      refute copilot_user.mobile_chat_disabled?
    end

    test "disabled if enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_mobile_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.mobile_chat_disabled?
      refute copilot_user.mobile_chat_enabled?
    end

    test "plan is business" do
      assert_equal "business", Copilot::User.new(@user).copilot_plan
    end
  end
end if GitHub.copilot_enabled?
