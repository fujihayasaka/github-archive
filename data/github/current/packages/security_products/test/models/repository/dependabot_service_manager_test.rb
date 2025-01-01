# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class Repository::DependabotServiceManagerTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    @user = create(:verified_user)
    @org  = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    make_trusted_oauth_apps_owner
    @dependabot = create(:dependabot_integration)
  end

  setup do
    GitHub.stubs(dependabot_enabled?: true) if GitHub.enterprise?
    reset_dependabot_github_app_memoization
    @manager = Repository::DependabotServiceManager.new(@repo)
  end

  context "#paused?" do
    test "returns false by default" do
      refute @manager.paused?
    end

    test "returns true if the paused key is set" do
      @repo.config.enable(Repository::DependabotServiceManager::PAUSED_KEY, @user)

      assert @manager.paused?
    end
  end

  context "#pause" do
    test "can be toggled from disabled to enabled" do
      refute @manager.paused?

      @manager.pause

      assert @manager.paused?
    end
  end

  context "#unpause" do
    test "can be toggled from enabled to disabled" do
      @repo.config.enable(Repository::DependabotServiceManager::PAUSED_KEY, @user)
      assert @manager.paused?

      @manager.unpause

      refute @manager.paused?
    end
  end
end
