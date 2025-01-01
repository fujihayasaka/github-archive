# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ConditionalPullRequestStateFilterJobTest < GitHub::TestCase
  include JobTestHelper
  include PullRequestIntegrationTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @open_pull = setup_pull_request(repository: @repo)
    @open_pull.status = "open"
    @open_pull.save

    @closed_pull = create(:pull_request, :with_mergeable_head, :closed, repository: @repo, user: @user)
    @closed_pull.status = "closed"
    @closed_pull.save

    @merged_pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    @merged_pull.issue.state = "closed"
    @merged_pull.issue.save
    @merged_pull.status = "closed"
    @merged_pull.merged_at = Time.now
    @merged_pull.save
  end

  setup do
    enable_feature_flag(:new_pull_request_state_filter)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  unless GitHub.enterprise?
    test "querying for open PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[open]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end

    test "querying for closed PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[closed]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end

    test "querying for closed or merged PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[closed merged]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end

    test "querying for closed or open PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[closed open]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end

    test "querying for merged PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[merged]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end

    test "querying for merged or open PRs returns no mismatches" do
      assert_nothing_raised do
        ConditionalPullRequestStateFilterJob.perform_now(
          ids: PullRequest.all.pluck(:id),
          states: %w[merged open]
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.conditional_state_filter", "result:match"]).length
    end
  end

end
