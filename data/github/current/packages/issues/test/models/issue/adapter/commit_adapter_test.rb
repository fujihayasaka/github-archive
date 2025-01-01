# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::PullRequestTestHelpers

  test "adapting a commit does not execute any queries" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user

    head_ref = pull.repository.heads.find_or_build(pull.head_ref)
    commit = append_dummy_commit(head_ref, commit_message: "Closes ##{issue.number}")

    create(:issue_event, event: "closed", issue: issue, actor: pull.owner, commit_id: commit.oid)

    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      # TODO: issue_timeline read commit from loader.context.commits (doesn't exist yet)
      _adapted, queries = log_cleaned_queries do
        Issue::Adapter::CommitAdapter.new(loader.context, commit: commit)
      end

      assert_equal 0, queries.count
    end
  end

  test "adapting a repository does not execute any queries" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user

    head_ref = pull.repository.heads.find_or_build(pull.head_ref)
    commit = append_dummy_commit(head_ref, commit_message: "Closes ##{issue.number}")

    create(:issue_event, event: "closed", issue: issue, actor: pull.owner, commit_id: commit.oid)

    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      # TODO: issue_timeline read commit from loader.context.commits (doesn't exist yet)
      _adapted, queries = log_cleaned_queries do
        Issue::Adapter::RepositoryAdapter.new(loader.context, repository: repo)
      end

      assert_equal 0, queries.count
    end
  end

  test "adapting a repository is wrapping the needed properties" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user

    head_ref = pull.repository.heads.find_or_build(pull.head_ref)
    commit = append_dummy_commit(head_ref, commit_message: "Closes ##{issue.number}")

    create(:issue_event, event: "closed", issue: issue, actor: pull.owner, commit_id: commit.oid, repository_id: repo.id)

    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      adapted = Issue::Adapter::RepositoryAdapter.new(loader.context, repository: repo)

      assert_equal repo.id, adapted.database_id
      assert_equal repo.name_with_display_owner, adapted.name_with_display_owner
    end
  end
end
