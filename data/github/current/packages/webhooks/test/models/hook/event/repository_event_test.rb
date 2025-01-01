# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventRepositoryEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user
    @repo = create :repository, owner: @org
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::RepositoryEvent, :action, :repository_id
  end

  context "#target_repository" do
    test "returns an active repository" do
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end

    test "returns a deleted repository" do
      @repo.remove(User.ghost, synchronous: true)
      event = Hook::Event::RepositoryEvent.new action: :deleted, repository_id: @repo.id, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil if a repository cannot be found" do
      invalid_repo_id = 0
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: invalid_repo_id, actor_id: @user.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true for deleted repos" do
      @repo.remove(User.ghost, synchronous: true)
      event = Hook::Event::RepositoryEvent.new action: :deleted, repository_id: @repo.id, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns true when an active repository is present" do
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns false when an active repository is not present" do
      invalid_repo_id = 0
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: invalid_repo_id, actor_id: @user.id
      refute_predicate event, :deliverable?
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context ".description" do
    test "returns human readable list" do
      assert_match /Repository created, deleted/, Hook::Event::RepositoryEvent.description
    end
  end

  context ".description_actions" do
    test "includes transferred events" do
      assert_includes Hook::Event::RepositoryEvent.description_actions, :transferred
    end

    test "includes renamed events" do
      assert_includes Hook::Event::RepositoryEvent.description_actions, :renamed
    end

    test "includes base events in description" do
      assert_includes Hook::Event::RepositoryEvent.description_actions, :created
    end

    test "includes anonymous access events if feature is enabled" do
      GitHub.stubs(:anonymous_git_access_enabled?).returns(true)
      assert_includes Hook::Event::RepositoryEvent.description_actions, :anonymous_access_enabled
    end
  end
end
