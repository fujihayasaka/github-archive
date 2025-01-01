# typed: true
# frozen_string_literal: true

require "test_helper"


class PullRequestAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::PullRequestTestHelpers

  test "adapting a pull request does not execute any queries" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user
    repo_owner = @make_pr_repo_owner
    create(:profile, user: repo_owner)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { pull.issue.update!(body: "Closes ##{issue.number}") }

    pull.merge(viewer)

    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      pull_request = loader.context.pull_requests_by_id[pull.id]
      _adapted, queries = log_cleaned_queries do
        Issue::Adapter::PullRequestAdapter.new(loader.context, pull_request: pull_request)
      end
      assert_equal 0, queries.count
    end
  end
end
