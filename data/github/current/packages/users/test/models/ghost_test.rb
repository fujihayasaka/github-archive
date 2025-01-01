# typed: true
# frozen_string_literal: true

require "test_helper"

class GhostsTest < GitHub::TestCase
  extend ExampleRepositories

  fixtures do
    @owner = create(:user)
    @repo  = create(:repository, owner: @owner, from_example: :pull_request_source)
    @user  = create(:user)
    forker = create(:user)
    @issue = create(:issue, repository: @repo, user: @owner)

    @repo.add_member(@user)
    @pull_fork = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :pull_request_fork)
    pull_issue = create(:issue, user: forker, repository: @repo)

    @pull = PullRequest.create_for(@repo,
      base: "master",
      head: "#{@pull_fork.user}:topic",
      user: pull_issue.user,
      issue: pull_issue)
  end

  test "ghost is a ghost" do
    assert User.ghost.ghost?
  end

  test "deleted creator" do
    @repo.add_member(@user)
    issue = create(:issue, user: @user, repository: @repo)

    assert_no_difference "Issue.count" do
      @user.destroy
    end

    issue.reload

    assert_equal User.ghost, issue.safe_user
  end

  test "deleted assignee" do
    @repo.add_member(@user)
    @issue.update!(assignee: @user)
    @user.destroy
    @issue.reload

    assert_nil @issue.assignee
  end

  context "safe_closed_by" do
    test "is ghost with a deleted closer" do
      @repo.add_member(@user)
      @issue.close(@user)
      @user.destroy
      @issue.reload

      assert_equal User.ghost, @issue.safe_closed_by
    end

    test "is ghost when the issue has no 'closed' events" do
      @repo.add_member(@user)
      @issue.close(@user)
      @issue.events.closes.destroy_all
      @issue.reload

      assert_equal User.ghost, @issue.safe_closed_by
    end

    test "is nil when the issue is open" do
      assert_nil @issue.safe_closed_by
    end
  end

  test "deleted re-opener" do
    @repo.add_member(@user)
    @issue.close(@owner)
    @issue.open(@user)
    @user.destroy
    @issue.reload

    assert_equal User.ghost, @issue.events.reopens.last.safe_actor
  end

  test "deleted merger" do
    @pull.merge(@user)
    @user.destroy
    @pull.reload

    assert_equal User.ghost, @pull.issue.events.merges.last.safe_actor
  end

  test "deleted commenter" do
    @repo.add_member(@user)
    @issue.comments.create!(user: @user, body: ":octocat:")
    @user.destroy
    @issue.reload

    assert_equal User.ghost, @issue.comments.last.safe_user
  end
end
