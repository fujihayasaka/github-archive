# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexAutomationDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "automation_enabled?" do
    context "dotcom" do
      test "always returns true" do
        memex = create(:memex_project)
        assert memex.automation_enabled?
      end
    end unless GitHub.enterprise?

    context "enterprise" do
      test "returns true if enabled by the business" do
        GitHub.enable_projects_automation(actor: @user)
        memex = create(:memex_project)
        assert memex.automation_enabled?
      end

      test "returns false if not enabled by the business" do
        GitHub.disable_projects_automation(actor: @user)
        memex = create(:memex_project)
        refute memex.automation_enabled?
      end
    end if GitHub.enterprise?
  end

  context "automation_enabled_for_user?" do
    context "dotcom" do
      test "returns true if user has write access" do
        memex = create(:memex_project)
        memex.grant_role(@user, :writer)

        assert memex.automation_enabled_for_user?(@user)
      end

      test "returns false if user does not have write access" do
        memex = create(:memex_project)

        refute memex.automation_enabled_for_user?(@user)
      end
    end unless GitHub.enterprise?

    context "enterprise" do
      test "returns true if enabled by the business and user has write access" do
        GitHub.enable_projects_automation(actor: @user)
        memex = create(:memex_project)
        memex.grant_role(@user, :writer)

        assert memex.automation_enabled_for_user?(@user)
      end

      test "returns false if not enabled by the business and user has write acces" do
        GitHub.disable_projects_automation(actor: @user)
        memex = create(:memex_project)
        memex.grant_role(@user, :writer)

        refute memex.automation_enabled_for_user?(@user)
      end

      test "returns false if not enabled by the business and user does not have write acces" do
        GitHub.disable_projects_automation(actor: @user)
        memex = create(:memex_project)

        refute memex.automation_enabled_for_user?(@user)
      end
    end if GitHub.enterprise?
  end
end
