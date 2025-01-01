# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDeleteEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user

    @creator = create(:user)
    @created_repo = create :repository, created_by_user_id: @creator.id

    @owner = create(:user)
    @owned_repo = create :repository, created_by_user_id: nil, owner: @owner
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DeleteEvent, :repository_id
  end

  context "#repository" do
    test "returns the specified repository" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_equal @repo, event.repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_nil event.repository
    end
  end

  context "#target_repository" do
    test "returns the specified repository" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_nil event.target_repository
    end
  end

  context "#ref_type" do
    test "returns :unknown if no ref is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_equal :unknown, event.ref_type
    end

    test "returns :tag if the ref is for a tag" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, ref: "refs/tags/v1"
      assert_equal :tag, event.ref_type
    end

    test "returns :branch if the ref is for a tag" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, ref: "refs/heads/feature-branch"
      assert_equal :branch, event.ref_type
    end
  end

  context "#branch_or_tag_name" do
    test "returns nil if no ref is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_nil event.branch_or_tag_name
    end

    test "returns the tag name if the ref is for a tag" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, ref: "refs/tags/v1"
      assert_equal "v1", event.branch_or_tag_name
    end

    test "returns branch name if the ref is for a tag" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, ref: "refs/heads/feature-branch"
      assert_equal "feature-branch", event.branch_or_tag_name
    end

    test "handles slashes in branch names" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, ref: "refs/heads/mdo/feature-branch"
      assert_equal "mdo/feature-branch", event.branch_or_tag_name
    end
  end

  context "#pusher" do
    test "returns nil if no pusher is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_nil event.pusher
    end

    test "raises an exception if the pusher is specified but not found" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, pusher_id: -1

      assert_raises ActiveRecord::RecordNotFound do
        event.pusher
      end
    end

    test "returns the pusher if specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, pusher_id: @user.id
      assert_equal @user, event.pusher
    end
  end

  context "#pusher_type" do
    test "returns :deploy_key if no pusher is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_equal :deploy_key, event.pusher_type
    end

    test "returns :user if the pusher is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, pusher_id: @user.id
      assert_equal :user, event.pusher_type
    end
  end

  context "#actor" do
    test "returns the pusher if the pusher is specified" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id, pusher_id: @user.id
      assert_equal @user, event.actor
    end

    test "returns the repo creator if no pusher is specied and the creator is known" do
      event = Hook::Event::DeleteEvent.new repository_id: @created_repo.id

      assert @created_repo.created_by
      assert_equal @creator, event.actor
    end

    test "returns the repo owner if no pusher is specied and the creator is unknown" do
      event = Hook::Event::DeleteEvent.new repository_id: @owned_repo.id

      assert_nil @owned_repo.created_by
      assert_equal @owner, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::DeleteEvent.new repository_id: @repo.id
      refute_predicate event, :deliverable?
    end
  end
end
