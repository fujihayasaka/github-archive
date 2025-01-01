# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"

# We test a vast majority of the PullRequest::ShowLoader functionality in the
# Issue::ShowLoaderTest.
class PullRequestShowLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include DogstatsTestHelpers
  include GitHub::PullRequestTestHelpers
  include IssueEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_fork)
    @pull = create(:pull_request, repository: @repo, user: @user)
  end

  context "with connected events" do
    test "preloads the issue's repository_id when it's different than the event's repository_id" do
      issue = create(:issue, repository: @repo, user: @user)
      # the pull request will get created with a new repository
      pull = create_connected_pull_request_events(issue)

      loader = PullRequest::ShowLoader.new(pull, @repo, @user, cap_filter: cap_authorizing_filter)
      assert_equal [pull.repository_id, issue.repository_id].sort, loader.context.repositories.map(&:id).sort
    end
  end

  context "#preload" do
    test "instuments timings for shared and prs-specific loaders" do
      PullRequest::ShowLoader.new(@pull, @repo, @user, cap_filter: cap_authorizing_filter)

      assert_dogstats_distribution "pull_request_loader.dist.time", tags: %w(fn:showloader:preload.shared)
      assert_dogstats_distribution "pull_request_loader.dist.time", tags: %w(fn:showloader:preload.prs_only)
    end

    test "tags review preloading" do
      PullRequest::ShowLoader.new(@pull, @repo, @user, cap_filter: cap_authorizing_filter)

      assert_dogstats_distribution "pull_request_loader.dist.time", tags: %w(
        defer_syntax_highlighted_diffs:true
        fn:showloader:preload_reviews
      )
    end
  end
end
