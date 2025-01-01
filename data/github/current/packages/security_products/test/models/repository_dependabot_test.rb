# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryDependabotTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @member = create(:user)
    @read_only = create(:user)
    @org.add_member(@member)
    @repo.add_member(@member, action: :write)
    @org.add_member(@read_only)
    @repo.add_member(@read_only, action: :read)
  end

  unless GitHub.dependabot_enabled?
    context "#automated_security_updates_visible_to?" do
      test "returns false when dependabot is disabled" do
        assert_equal false, @repo.automated_security_updates_visible_to?(@user)
      end
    end

    context "#automated_security_updates_configurable_by?" do
      test "returns false when dependabot is disabled" do
        assert_equal false, @repo.automated_security_updates_configurable_by?(@user)
      end
    end

    context "#automated_dependency_updates_visible_to?" do
      test "returns false when dependabot is disabled" do
        assert_equal false, @repo.automated_dependency_updates_visible_to?(@user)
        assert_equal false, @repo.automated_dependency_updates_visible_to?(@member)
      end
    end
  end

  if GitHub.dependabot_enabled?
    context "#automated_security_updates_visible_to?" do
      test "returns true for users that can see vulnerability alerts" do
        assert_equal true, @repo.automated_security_updates_visible_to?(@user)
        assert_equal false, @repo.automated_security_updates_visible_to?(@read_only)
        assert_equal false, @repo.automated_security_updates_visible_to?(nil)

        @repo.vulnerability_manager.replace_vulnerability_alert_restricted_users_and_teams(
          user_ids: [@read_only.id],
          team_ids: [],
        )
        @repo.save!
        @repo = Repositories::Public.find_active!(@repo.id)

        assert_equal true, @repo.automated_security_updates_visible_to?(@user)
        assert_equal true, @repo.automated_security_updates_visible_to?(@read_only)
        assert_equal false, @repo.automated_security_updates_visible_to?(nil)
      end
    end

    context "#automated_security_updates_configurable_by?" do
      test "returns true if dependabot is visible" do
        @repo.disable_dependency_graph_and_vulnerability_alerts(actor: @user)

        assert_equal false, @repo.automated_security_updates_configurable_by?(@user)
        assert_equal false, @repo.automated_security_updates_configurable_by?(@read_only)
        assert_equal false, @repo.automated_security_updates_configurable_by?(nil)

        @repo.force_enable_vulnerability_alerts(actor: @user)

        assert_equal true, @repo.automated_security_updates_configurable_by?(@user)
        assert_equal false, @repo.automated_security_updates_configurable_by?(@read_only)
        assert_equal false, @repo.automated_security_updates_configurable_by?(nil)
      end
    end

    context "#automated_dependency_updates_visible_to?" do
      test "returns true for users with repo write access" do
        assert_equal true, @repo.automated_dependency_updates_visible_to?(@user)
        assert_equal true, @repo.automated_dependency_updates_visible_to?(@member)
        assert_equal false, @repo.automated_dependency_updates_visible_to?(@read_only)
        assert_equal false, @repo.automated_dependency_updates_visible_to?(nil)
      end
    end
  end
end
