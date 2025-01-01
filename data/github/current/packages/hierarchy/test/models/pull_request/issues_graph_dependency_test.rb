# typed: true
# frozen_string_literal: true
# fixed: true
require "test_helper"

class PullRequest::IssuesGraphDependencyTest < GitHub::TestCase
  # include GitHub::LoggerHelper
  # include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @nwo = @repo.full_name.split("/")
    GitHub.flipper[:tasklist_block].enable(@user)
  end

  test "to hierarchy model (merged)" do
    pull = create(:pull_request, :merged, :disable_disk_access, repository: @repo)
    issue = pull.issue
    key = issue.to_hierarchy_model_key
    expected = {
      key: key,
      title: issue.title,
      url: pull.url,
      state: :merged,
      stateReason: issue.state_reason,
      userName: @nwo[0],
      repoName: @nwo[1],
      number:   pull.number,
      repoId: pull.repository_id,
      assignees: issue.assignees.map(&:to_hierarchy_model),
      labels: issue.labels.map(&:to_hierarchy_model),
      itemType: "PULL_REQUEST",
    }
    assert_equal expected, pull.to_hierarchy_model
  end

  test "to hierarchy model (open)" do
    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    issue = pull.issue
    key = issue.to_hierarchy_model_key
    expected = {
      key: key,
      title: issue.title,
      url: pull.url,
      state: :open,
      stateReason: issue.state_reason,
      userName: @nwo[0],
      repoName: @nwo[1],
      number:   pull.number,
      repoId: pull.repository_id,
      assignees: issue.assignees.map(&:to_hierarchy_model),
      labels: issue.labels.map(&:to_hierarchy_model),
      itemType: "PULL_REQUEST",
    }
    assert_equal expected, pull.to_hierarchy_model
  end

  test "to hierarchy model (closed)" do
    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    pull.close
    issue = pull.issue
    key = issue.to_hierarchy_model_key
    expected = {
      key: key,
      title: issue.title,
      url: pull.url,
      state: :closed,
      stateReason: issue.state_reason,
      userName: @nwo[0],
      repoName: @nwo[1],
      number:   pull.number,
      repoId: pull.repository_id,
      assignees: issue.assignees.map(&:to_hierarchy_model),
      labels: issue.labels.map(&:to_hierarchy_model),
      itemType: "PULL_REQUEST",
    }
    assert_equal expected, pull.to_hierarchy_model
  end

  test "to hierarchy model key" do
    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    issue = pull.issue
    key = {
      ownerId:   @repo.owner_id,
      itemId:  issue.id,
    }
    assert_equal key, pull.to_hierarchy_model_key
  end

  test "returns nil if FF is not enabled." do
    GitHub.flipper[:tasklist_block].disable(@user)
    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    refute pull.to_hierarchy_model
    refute pull.to_hierarchy_model_key
  end

  context "sync_issues_graph_data" do
    test "ff is not enabled" do
      GitHub.flipper[:issues_graph_api].enable
      GitHub.flipper[:tasklist_block].disable

      pull = create(:pull_request, :draft, :disable_disk_access, repository: @repo, draft: true)
      pull_as_hierarchy_model = pull.to_hierarchy_model
      assert pull.draft?

      SyncIssueToIssuesGraphJob.expects(:perform_later).never

      pull.ready_for_review!(user: @user)
    end

    test "updates issues graph state when PR changes from draft to open" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :draft, :disable_disk_access, repository: @repo, draft: true)
      pull_as_hierarchy_model = pull.to_hierarchy_model
      assert pull.draft?

      expected = pull_as_hierarchy_model.merge(state: :open)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.ready_for_review!(user: @user)
    end

    test "updates issues graph state when PR changes from open to draft" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :disable_disk_access, repository: @repo)
      pull_as_hierarchy_model = pull.to_hierarchy_model
      refute pull.draft?

      expected = pull_as_hierarchy_model.merge(state: :draft)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.convert_to_draft(user: @user)
    end

    test "updates issues graph state when PR changes from draft to close" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :disable_disk_access, repository: @repo, draft: true)
      pull_as_hierarchy_model = pull.to_hierarchy_model
      assert pull.draft?

      expected = pull_as_hierarchy_model.merge(state: :closed)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.issue.update(state: "closed")
    end

    test "updates issues graph state when PR changes from close to draft" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :closed, :disable_disk_access, repository: @repo, draft: true)
      pull_as_hierarchy_model = pull.to_hierarchy_model
      assert_equal :closed, pull.state
      assert pull.draft?

      expected = pull_as_hierarchy_model.merge(state: :draft)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.issue.update(state: "open")
    end

    test "updates issues graph state when PR changes from open to close" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :disable_disk_access, repository: @repo)
      pull_as_hierarchy_model = pull.to_hierarchy_model

      expected = pull_as_hierarchy_model.merge(state: :closed)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.issue.update(state: "closed")
    end

    test "updates issues graph state when PR changes from close to open" do
      GitHub.flipper[:issues_graph_api].enable

      pull = create(:pull_request, :closed, :disable_disk_access, repository: @repo)
      pull_as_hierarchy_model = pull.to_hierarchy_model

      expected = pull_as_hierarchy_model.merge(state: :open)
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      pull.issue.update(state: "open")
    end
  end
end
