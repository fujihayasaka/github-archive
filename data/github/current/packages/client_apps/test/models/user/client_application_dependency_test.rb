# typed: true
# frozen_string_literal: true

require "test_helper"

class ClientApplicationDependencyTest < GitHub::TestCase
  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
    @paid_user = create(:user, login: "paid-user", email: "paid-user@example.com", plan: "medium")
  end

  context "toggling client app flags" do

    test "toggling the desktop app flag" do
      assert !User.new.desktop_app_enabled?
      assert !@paid_user.desktop_app_enabled?
      assert !@paid_user.has_app_enabled?

      @paid_user.enable_desktop_app(:mac)
      assert @paid_user.desktop_app_enabled?
      assert @paid_user.has_app_enabled?
    end

    test "toggling the VisualStudio app flag" do
      assert !User.new.visual_studio_app_enabled?
      assert !@paid_user.visual_studio_app_enabled?
      assert !@paid_user.has_app_enabled?

      @paid_user.enable_visual_studio_app
      assert @paid_user.visual_studio_app_enabled?
      assert @paid_user.has_app_enabled?
    end

    test "toggling the xcode app flag" do
      assert !User.new.xcode_app_enabled?
      assert !@paid_user.xcode_app_enabled?
      assert !@paid_user.has_app_enabled?

      @paid_user.enable_xcode_app
      assert @paid_user.xcode_app_enabled?
      assert @paid_user.has_app_enabled?
    end
  end

  context "client app enabled? methods memoizes result" do

    test "#visual_studio_app_enabled? memoizes result" do
      ClientApplicationSet.any_instance.expects(:include?).once
      @free_user.visual_studio_app_enabled?
      @free_user.visual_studio_app_enabled?
    end
  end
end
