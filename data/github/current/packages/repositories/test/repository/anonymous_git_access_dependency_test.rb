# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAnonymousGitAccessTest < GitHub::TestCase
  fixtures do
    @user = create :paid_user # users repo will be made private
    @forker = create :paid_user # users fork will be made private
    @staff = create :staff_admin_user

    @repo = create :repository, owner: @user
    @repo_fork = create(:fork_repository, forker: @forker, fork_repo: @repo)

    @org = create :organization
    @org_repo = create :repository, owner: @org
    @org_repo_fork = create(:fork_repository, forker: @forker, fork_repo: @org_repo)
  end

  setup do
    GitHub.enable_anonymous_git_access(@staff)
    @private_mode, GitHub.private_mode = GitHub.private_mode, true
  end

  teardown do
    GitHub.private_mode, @private_mode = @private_mode, nil
  end

  context "for user-owned repos" do
    test "is disabled when feature is globally disabled" do
      GitHub.disable_anonymous_git_access(@staff)

      @repo.enable_anonymous_git_access(@user)
      refute @repo.anonymous_git_access_enabled?
    end

    test "is disabled when repository is private" do
      @repo.enable_anonymous_git_access(@user)
      @repo.public = false
      refute @repo.anonymous_git_access_enabled?
    end

    test "reflects anonymous_git_access_enabled" do
      @repo.enable_anonymous_git_access(@user)
      assert @repo.anonymous_git_access_enabled?

      @repo.disable_anonymous_git_access(@user)
      refute @repo.anonymous_git_access_enabled?
    end

    test "can be changed by site admins when locked" do
      @repo.lock_anonymous_git_access(@staff)
      @repo.enable_anonymous_git_access(@staff)
      assert @repo.anonymous_git_access_enabled?
    end

    test "raises an error when changing anonymous git access on a fork" do
      assert_raises Repository::AnonymousGitAccess::Error do
        @repo_fork.enable_anonymous_git_access(@staff)
      end
    end

    test "raises an error when non-site admins change locked anonymous git access" do
      @repo.lock_anonymous_git_access(@staff)
      assert_raises Repository::AnonymousGitAccess::Error do
        @repo.enable_anonymous_git_access(@user)
      end
    end

    test "reflects root.anonymous_git_access_enabled if a fork" do
      @repo.enable_anonymous_git_access(@user)
      assert @repo_fork.anonymous_git_access_enabled?
    end

    test "network repos reflect root anonymous git access after network change" do
      @repo.enable_anonymous_git_access(@user)

      other_forker = create :user
      repo_fork_fork = create(:fork_repository, forker: other_forker, fork_repo: @repo_fork)

      @repo_fork.toggle_visibility(actor: @forker)

      # the nested fork should be reparented and still get anonymous access from
      # the root, @org_repo
      assert repo_fork_fork.anonymous_git_access_enabled?

      # after being made private, this repo shouldn't have anonymous git access
      refute @repo_fork.anonymous_git_access_enabled?
    end

    test "creates audit log entries when enabled" do
      events = subscribe("repo.config.enable_anonymous_git_access")
      @repo.enable_anonymous_git_access(@user)
      assert_equal 1, events.size

      event = events.first
      assert_equal @user.id, event.payload[:actor_id]
      assert_equal @repo.id, event.payload[:repo_id]
      assert_nil event.payload[:org_id]
    end

    test "creates audit log entries when disabled" do
      @repo.enable_anonymous_git_access(@user)

      events = subscribe("repo.config.disable_anonymous_git_access")
      @repo.disable_anonymous_git_access(@user)
      assert_equal 1, events.size

      event = events.first
      assert_equal @user.id, event.payload[:actor_id]
      assert_equal @repo.id, event.payload[:repo_id]
      assert_nil event.payload[:org_id]
    end
  end

  context "for organization-owned repos" do
    test "is disabled when feature is globally disabled" do
      GitHub.disable_anonymous_git_access(@user)

      @org_repo.enable_anonymous_git_access(@user)
      refute @org_repo.anonymous_git_access_enabled?
    end

    test "is disabled when repository is private" do
      @org_repo.enable_anonymous_git_access(@user)
      @org_repo.public = false
      refute @org_repo.anonymous_git_access_enabled?
    end

    test "reflects anonymous_git_access_enabled" do
      @org_repo.enable_anonymous_git_access(@user)
      assert @org_repo.anonymous_git_access_enabled?

      @org_repo.disable_anonymous_git_access(@user)
      refute @org_repo.anonymous_git_access_enabled?
    end

    test "can be changed by site admins when locked" do
      @org_repo.lock_anonymous_git_access(@staff)
      @org_repo.enable_anonymous_git_access(@staff)
      assert @org_repo.anonymous_git_access_enabled?
    end

    test "raises an error when changing anonymous git access on a fork" do
      assert_raises Repository::AnonymousGitAccess::Error do
        @org_repo_fork.enable_anonymous_git_access(@staff)
      end
    end

    test "raises an error when non-site admins change locked anonymous git access" do
      @org_repo.lock_anonymous_git_access(@staff)
      assert_raises Repository::AnonymousGitAccess::Error do
        @org_repo.enable_anonymous_git_access(@user)
      end
    end

    test "reflects root.anonymous_git_access_enabled if a fork" do
      @org_repo.enable_anonymous_git_access(@user)
      assert @org_repo_fork.anonymous_git_access_enabled?
    end

    test "network repos reflect root anonymous git access after network change" do
      @org_repo.enable_anonymous_git_access(@user)

      other_forker = create :user
      org_repo_fork_fork = create(:fork_repository, forker: other_forker, fork_repo: @org_repo_fork)

      @org_repo_fork.toggle_visibility(actor: @forker)

      # the nested fork should be reparented and still get anonymous access from
      # the root, @org_repo
      assert org_repo_fork_fork.anonymous_git_access_enabled?

      # after being made private, this repo shouldn't have anonymous git access
      refute @org_repo_fork.anonymous_git_access_enabled?
    end

    test "creates audit log entries when enabled" do
      events = subscribe("repo.config.enable_anonymous_git_access")
      @org_repo.enable_anonymous_git_access(@user)
      assert_equal 1, events.size

      event = events.first
      assert_equal @user.id, event.payload[:actor_id]
      assert_equal @org_repo.id, event.payload[:repo_id]
      assert_equal @org.id, event.payload[:org_id]
    end

    test "creates audit log entries when disabled" do
      @org_repo.enable_anonymous_git_access(@user)

      events = subscribe("repo.config.disable_anonymous_git_access")
      @org_repo.disable_anonymous_git_access(@user)
      assert_equal 1, events.size

      event = events.first
      assert_equal @user.id, event.payload[:actor_id]
      assert_equal @org_repo.id, event.payload[:repo_id]
      assert_equal @org.id, event.payload[:org_id]
    end
  end

  context "#anonymous_git_access_available?" do
    test "returns true if anonymous access is globally available and repo is public" do
      assert @repo.anonymous_git_access_available?
    end

    test "returns false if repo is private" do
      @repo.public = false
      refute @repo.anonymous_git_access_available?
    end

    test "returns false if anonymous access is not globally available" do
      GitHub.disable_anonymous_git_access(@staff)
      refute @repo.anonymous_git_access_available?
    end
  end

  context "with_anonymous_git_access scope" do
    test "can find all User- and Org-owned repos that have anonymous access enabled" do
      @repo.enable_anonymous_git_access(@user)
      @org_repo.enable_anonymous_git_access(@user)

      repositories = Repository.with_anonymous_git_access
      assert repositories.include?(@repo)
      assert repositories.include?(@org_repo)
    end

    test "returns nothing if feature is disabled" do
      @repo.enable_anonymous_git_access(@user)
      @org_repo.enable_anonymous_git_access(@user)

      GitHub.disable_anonymous_git_access(@staff)

      assert Repository.with_anonymous_git_access.empty?
    end

    test "only returns active, public repositories" do
      repo_private = create(:private_repository, owner: @user)
      repo_inactive = create(:repository, owner: @user)
      repo_inactive.update(active: nil)

      @repo.enable_anonymous_git_access(@user)
      repo_private.enable_anonymous_git_access(@user)
      repo_inactive.enable_anonymous_git_access(@user)

      repositories = Repository.with_anonymous_git_access
      assert repositories.include?(@repo)
      refute repositories.include?(repo_private)
      refute repositories.include?(repo_inactive)
    end

    test "can find forks whose parents have anonymous access enabled" do
      user2 = create(:user)
      user3 = create(:user)
      repo_fork = create(:fork_repository, forker: user2, fork_repo: @repo)
      repo_fork_fork = create(:fork_repository, forker: user3, fork_repo: repo_fork)

      assert_difference "Configuration::Entry.count" do
        @repo.enable_anonymous_git_access(@user)
      end

      assert repo_fork.anonymous_git_access_enabled?
      assert repo_fork_fork.anonymous_git_access_enabled?

      repositories = Repository.with_anonymous_git_access
      assert repositories.include?(@repo)
      assert repositories.include?(repo_fork)
      assert repositories.include?(repo_fork_fork)
    end

    test "does not return a fork that's been removed from its parent's network" do
      user2 = create(:user)
      user3 = create(:paid_user) # user's fork is being made private
      repo_fork = create(:fork_repository, forker: user2, fork_repo: @repo)
      repo_fork_fork = create(:fork_repository, forker: user3, fork_repo: repo_fork)

      assert_difference "Configuration::Entry.count" do
        @repo.enable_anonymous_git_access(@user)
      end

      assert repo_fork.anonymous_git_access_enabled?
      assert repo_fork_fork.anonymous_git_access_enabled?
      repo_fork_fork.toggle_visibility(actor: user3)

      repositories = Repository.with_anonymous_git_access
      assert repositories.include?(@repo)
      assert repositories.include?(repo_fork)
      refute repositories.include?(repo_fork_fork)
    end

    test "calling via User#anonymous_access_repositories only returns repos owned by the user" do
      @repo.enable_anonymous_git_access(@user)
      @org_repo.enable_anonymous_git_access(@user)

      repositories = @user.anonymous_access_repositories
      assert repositories.include?(@repo)
      refute repositories.include?(@org_repo)
    end

    test "calling via Organization#anonymous_access_repositories only returns repos owned by the org" do
      @repo.enable_anonymous_git_access(@user)
      @org_repo.enable_anonymous_git_access(@user)

      repositories = @org.anonymous_access_repositories
      refute repositories.include?(@repo)
      assert repositories.include?(@org_repo)
    end
  end
end
