# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryIgnoreDependencyTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:user)
    @repo = create(:repository, owner: @repo_owner)
    @rando = create(:user)
  end

  context "#blocked_from_commenting?" do
    test "returns false for a private repository regardless of given user or commentable" do
      private_repo = create(:private_repository, has_discussions: true, owner: @repo_owner)
      private_repo.add_member(@rando)
      @repo_owner.block(@rando)
      issue = create(:issue, repository: private_repo)
      discussion = create(:discussion, repository: private_repo)
      pull_request = create(:pull_request, :disable_disk_access, repository: private_repo, user: @repo_owner)
      commentables = [issue, discussion, pull_request]
      users = [nil, @repo_owner, @rando]

      commentables.each do |commentable|
        users.each do |user|
          refute private_repo.blocked_from_commenting?(user: user, commentable: commentable)
        end
      end
    end

    test "returns false when no commentable is given" do
      @repo_owner.block(@rando)
      refute @repo.blocked_from_commenting?(user: @rando, commentable: nil)
    end

    test "returns false for user who has push access to the repo" do
      user_with_push_access = @rando
      @repo.add_member(user_with_push_access, action: :write)
      commentable = create(:issue, repository: @repo)
      commentable_author = commentable.user
      commentable_author.block(user_with_push_access)

      refute @repo.blocked_from_commenting?(user: user_with_push_access, commentable: commentable)
    end

    test "returns true when repo owner has blocked the user" do
      @repo_owner.block(@rando)
      commentable = create(:issue, repository: @repo)
      assert @repo.blocked_from_commenting?(user: @rando, commentable: commentable)
    end

    test "returns true when author of commentable has blocked the user" do
      commentable = create(:issue, repository: @repo)
      commentable.user.block(@rando)

      assert @repo.blocked_from_commenting?(user: @rando, commentable: commentable)
    end

    test "returns false for anonymous viewer" do
      commentable = create(:issue, repository: @repo)
      refute @repo.blocked_from_commenting?(user: nil, commentable: commentable)
    end
  end

  context "#owner_blocking?" do
    test "returns true when repository's owner is blocking the given user" do
      @repo_owner.block(@rando)
      assert @repo.owner_blocking?(@rando)
    end

    test "returns false when given nil" do
      refute @repo.owner_blocking?(nil)
    end

    test "returns false when repository's owner is not blocking the given user" do
      refute @repo.owner_blocking?(@rando)
    end

    test "returns false when given the repository's owner" do
      refute @repo.owner_blocking?(@repo_owner)
    end

    test "memoizes result by user ID" do
      blocked_user = create(:user)
      @repo_owner.block(blocked_user)

      assert_query_count(1) do
        assert @repo.owner_blocking?(blocked_user)
      end
      assert_query_count(0) do
        assert @repo.owner_blocking?(blocked_user)
      end

      assert_query_count(1) do
        refute @repo.owner_blocking?(@rando)
      end
      assert_query_count(0) do
        refute @repo.owner_blocking?(@rando)
      end
    end
  end
end
