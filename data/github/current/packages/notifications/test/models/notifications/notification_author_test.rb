# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationAuthorTest < GitHub::TestCase
  include Notifications::TestHelper
  include CommitTestHelper

  fixtures do
    @owner, @author, @thread_author = create_users :owner, :author, :threadauthor
    @org, team = create_org @owner
    @repo = create(:repository, owner: @org, name: "repo", from_example: :pull_request_source)
    team.add_repository(@repo, :push)
    fork = create(:fork_repository, forker: @thread_author, fork_repo: @repo, from_example: :pull_request_fork)

    @issue = create(:issue, user: @thread_author, repository: @repo)

    @pr = create :pull_request, issue: @issue,
      base_repository:  @repo,
      base_user:  @org,
      base_ref:  "master",
      head_repository:  fork,
      head_user:  @thread_author,
      head_ref:  "topic"
  end

  test "issues can return their notification author" do
    assert_equal @thread_author, @issue.notifications_author
  end

  test "issue comments can return their notification author" do
    issue_comment = create(:issue_comment, issue: @issue)
    assert_equal @thread_author, issue_comment.notifications_author
  end

  test "pull requests can return their notification author" do
    assert_equal @thread_author, @pr.notifications_author
  end

  test "pull request reviews can return their notification author" do
    pr_review = create(:pull_request_review, user: @thread_author, pull_request: @pr)
    assert_equal @thread_author, pr_review.notifications_author
  end

  test "pull request review comments can return their notification author" do
    pr_review_comment = create(:pull_request_review_comment, user: @thread_author, pull_request: @pr)
    assert_equal @thread_author, pr_review_comment.notifications_author
  end

  test "pushes can return their notification author" do
    ref = @repo.heads.find("master").target
    push = create(:push, pusher: @thread_author, ref: "master", repository: @repo, before: ref.to_s, after: ref.to_s)
    assert_equal @thread_author, push.notifications_author
  end

  test "releases can return their notification author" do
    release = create(:release, repository: @repo, author: @thread_author, state: :draft)
    assert_equal @thread_author, release.notifications_author
  end

  test "repo invitations can return their notification author" do
    repo_invitation = create(:repository_invitation, inviter: @thread_author)
    assert_equal @thread_author, repo_invitation.notifications_author
  end

  test "commit comments can return their notification author" do
    commit = @repo.heads.find("master").target
    commit_comment = create(:commit_comment,
      user: @thread_author,
      repository: @repo,
      commit_id: commit.oid,
      body: "This is a commit",
    )
    assert_equal @thread_author, commit_comment.notifications_author
  end

  test "commit mentions can return their notification author" do
    commit = create_commit(repo: @repo, user: @thread_author)
    commit_mention = CommitMention.create(repository: @repo, commit_id: commit.oid)
    assert_equal @thread_author, commit_mention.notifications_author
  end

  test "commit can return their notification author" do
    commit = create_commit(repo: @repo, user: @thread_author)
    assert_equal @thread_author, commit.notifications_author
  end

  context "IssueEvent" do
    test "assigned issue events use the subject as notification author" do
      issue_event = create(:issue_event, actor: @thread_author, event: "assigned")
      issue_event_detail = issue_event.issue_event_detail
      issue_event_detail.subject = @owner
      issue_event_detail.save!

      assert_equal @owner, issue_event.notifications_author
    end

    test "non-assigned issue events use the actor as notification author" do
      issue_event = create(:issue_event, actor: @thread_author, event: "closed")
      issue_event_detail = issue_event.issue_event_detail
      issue_event_detail.subject = @owner
      issue_event_detail.save!

      assert_equal @thread_author, issue_event.notifications_author
    end

    test "issue events default to issue author when no issue event author" do
      issue_event = create(:issue_event, actor: @author, event: "assigned", issue: @issue)

      assert_equal @thread_author, issue_event.notifications_author
    end
  end
end
