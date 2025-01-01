# typed: true
# frozen_string_literal: true

require "test_helper"


class IssueOrPullRequestHovercardContextsViewerInvolvementHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @collaborator = create(:user)
    @repo = create(:repository)
    @repo.add_member(@collaborator)
  end

  def async_resolve(*args, **kwargs)
    T.unsafe(IssueOrPullRequestHovercard::Contexts::ViewerInvolvement).async_resolve(*args, **kwargs)
  end

  context ".async_resolve" do
    test "returns a context with a message when viewer is assigned to an issue" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, assignee: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to this issue", context.message
    end

    test "returns a context with a message when viewer opened an issue" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, user: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You opened this issue", context.message
    end

    test "returns a context with a message when viewer comments on an issue" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo)
      create(:issue_comment, issue: issue, user: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You commented on this issue", context.message
    end

    test "returns a context with a message when viewer is mentioned on an issue" do
      viewer = @collaborator
      other_user = create(:user)
      only = [SubscribeAndNotifyJob]
      issue = perform_enqueued_jobs(only: only) do
        create(:issue, repository: @repo, user: other_user, body: "yo @#{viewer}")
      end
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You were mentioned on this issue", context.message
    end

    test "returns a context with a message when viewer has opened and commented on an issue" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, user: viewer)
      create(:issue_comment, issue: issue, user: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You commented on and opened this issue", context.message
    end

    test "returns a context with a message when viewer has been assigned and commented on an issue" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, assignee: viewer)
      create(:issue_comment, issue: issue, user: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to and commented on this issue", context.message
    end

    test "prioritizes 'assigned' -> 'mentioned' -> 'commented' -> 'opened' when all contexts exist for an issue" do
      viewer = @collaborator
      only = [SubscribeAndNotifyJob]
      issue = perform_enqueued_jobs(only: only) do
        create(:issue, repository: @repo, user: viewer, assignee: viewer, body: "yo @#{viewer}")
      end
      other_user = create(:user)
      create(:issue_comment, issue: issue, user: viewer)
      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to and were mentioned on this issue", context.message
    end

    test "returns a context with a message when viewer is assigned to a PR" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, assignee: viewer)
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to this pull request", context.message
    end

    test "returns a context with a message when viewer opened a PR" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, user: viewer)
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You opened this pull request", context.message
    end

    test "returns a context with a message when viewer comments on a PR" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo)
      create(:issue_comment, issue: issue, user: viewer)
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You commented on this pull request", context.message
    end

    test "returns a context with a message when viewer is mentioned on a PR" do
      viewer = @collaborator
      other_user = create(:user)
      issue = create(:issue, repository: @repo)
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        create(:issue_comment, :wait_for_orchestration, issue: issue, body: "yo @#{viewer}")
      end
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You were mentioned on this pull request", context.message
    end

    test "returns a context with a message when viewer has been assigned and commented on an PR" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo, assignee: viewer)
      create(:issue_comment, issue: issue, user: viewer)
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to and commented on this pull request", context.message
    end

    test "prioritizes 'assigned' -> 'mentioned' -> 'commented' -> 'opened' when all contexts exist for a PR" do
      viewer = @collaborator
      only = [SubscribeAndNotifyJob]
      issue = perform_enqueued_jobs(only: only) do
        create(:issue, repository: @repo, assignee: viewer, user: viewer, body: "yo @#{viewer}")
      end
      create(:issue_comment, issue: issue, user: viewer)
      pr = create(:pull_request, :disable_disk_access, issue: issue)
      context = async_resolve(issue_or_pull_request: pr, viewer: viewer).sync

      refute_nil context
      assert_equal "You are assigned to and were mentioned on this pull request", context.message
    end
  end
end
