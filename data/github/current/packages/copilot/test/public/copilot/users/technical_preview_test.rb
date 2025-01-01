# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersTechnicalPreviewTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org.add_member(@user)
  end

  context "#technical_preview_user_lost_access?" do
    test "is false when user is not a technical preview user" do
      refute Copilot::User.new(@user).technical_preview_user_lost_access?
    end

    test "is true when user is a technical preview user" do
      create(:copilot_technical_preview_user, user: @user, subscribed: false)
      assert Copilot::User.new(@user).technical_preview_user_lost_access?
    end

    test "is false when user is a technical preview user but subscribed" do
      create(:copilot_technical_preview_user, user: @user, subscribed: true)
      refute Copilot::User.new(@user).technical_preview_user_lost_access?
    end
  end

  context "#is_technical_preview_user?" do
    test "is false when the user has not TP record" do
      refute Copilot::User.new(@user).is_technical_preview_user?
    end

    test "is false when the user is does not have an EAM" do
      create(:copilot_technical_preview_user, user: @user)
      assert Copilot::User.new(@user).is_technical_preview_user?
    end
  end

  context "#async_is_technical_preview_user?" do
    test "is false when the user has not TP record" do
      refute Copilot::User.new(@user).async_is_technical_preview_user?.sync
    end

    test "is false when the user is does not have an EAM" do
      create(:copilot_technical_preview_user, user: @user)
      assert Copilot::User.new(@user).async_is_technical_preview_user?.sync
    end
  end
end if GitHub.copilot_enabled?
