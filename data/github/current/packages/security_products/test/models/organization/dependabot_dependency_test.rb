# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class DependabotDependencyTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    @admin = create(:user)
    @org   = create(:organization, admin: @admin)

    make_trusted_oauth_apps_owner
    @dependabot_integration = create(:dependabot_integration)
  end

  setup do
    GitHub.stubs(dependabot_enabled?: true) if GitHub.enterprise?
    reset_dependabot_github_app_memoization
  end

  context "#dependabot_repository_access_enabled_for?" do
    test "returns true for an admin" do
      assert @org.dependabot_repository_access_enabled_for?(@admin)
    end

    test "returns false for nil user" do
      refute @org.dependabot_repository_access_enabled_for?(nil)
    end

    test "returns false for non admin user" do
      non_admin = create(:user)

      refute @org.dependabot_repository_access_enabled_for?(non_admin)
    end

    test "returns false on enterprise if Dependabot is disabled", enterprise_only: true do
      GitHub.stubs(dependabot_enabled?: false)
      refute @org.dependabot_repository_access_enabled_for?(@admin)
    end
  end

  context "#dependabot_installed?" do
    test "returns true when dependabot installed for all repos" do
      make_integration_installation(integration: @dependabot_integration, target: @org)

      assert @org.dependabot_installed?
    end

    test "returns true when dependabot installed for selected repos" do
      repo = create(:private_repository, owner: @org, name: "alpha")
      make_integration_installation(integration: @dependabot_integration, target: @org, repositories: [repo])

      assert @org.dependabot_installed?
    end

    test "returns false when dependabot is not installed" do
      refute @org.dependabot_installed?
    end
  end
end
