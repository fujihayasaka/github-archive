# typed: true
# frozen_string_literal: true

require "test_helper"

class ClientApplicationDependencyTest < GitHub::TestCase
  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
    @paid_user = create(:user, login: "paid-user", email: "paid-user@example.com", plan: "medium")
    @desktop_app = create(:github_desktop_app)
    @visual_studio_app = create(:visual_studio_oauth_app)
  end

  context "toggling client app flags" do

    test "toggling the desktop app flag based on OAuth access" do
      refute User.new.desktop_app_enabled?
      refute User.new.has_app_enabled?

      user = create(:user)
      make_oauth(user, ["user"], @desktop_app)

      assert user.desktop_app_enabled?
      assert user.has_app_enabled?
    end

    test "toggling the VisualStudio app flag based on OAuth access" do
      refute User.new.visual_studio_app_enabled?
      refute User.new.has_app_enabled?

      user = create(:user)
      make_oauth(user, ["user"], @visual_studio_app)

      assert user.visual_studio_app_enabled?
      assert user.has_app_enabled?
    end
  end

  context "client app enabled? methods memoizes result" do

    test "#visual_studio_app_enabled? memoizes result" do
      assert_query_count(1) do
        @free_user.visual_studio_app_enabled?
      end
      assert_query_count(0) do
        @free_user.visual_studio_app_enabled?
      end
    end
  end
end
