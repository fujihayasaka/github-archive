# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RestApiStatusFilterExperimentJobTest < GitHub::TestCase
  include JobTestHelper
  include PullRequestIntegrationTestHelpers

  fixtures do
    @user = create(:user)
    @second_user = create(:user)
    @third_user = create(:user)
    @repo = create(:repository, from_example: :pull_request_source, owner: @user)
    @repo.add_member @second_user, action: :write
    @repo.add_member @third_user, action: :write

    @open_pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    @open_pull.update(status: "open")

    @closed_pull = create(:pull_request, :with_mergeable_head, :closed, repository: @repo, user: @second_user)
    @closed_pull.update(status: "closed")

    @merged_pull = create(:pull_request, :with_mergeable_head, :merged, repository: @repo, user: @third_user)
    @merged_pull.update(status: "closed")

    @indifferent_params = {
      base: "master",
      head: "topic"
    }
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  unless GitHub.enterprise?
    test "querying for open PRs returns no mismatches" do
      assert_nothing_raised do
        RestApiStatusFilterExperimentJob.perform_now(
          repository_id: @repo.id,
          user_id: @user.id,
          indifferent_params: @indifferent_params.merge(state: "open")
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.rest_api_status_filter", "result:match"]).length
    end

    test "querying for closed PRs returns no mismatches" do
      assert_nothing_raised do
        RestApiStatusFilterExperimentJob.perform_now(
          repository_id: @repo.id,
          user_id: @user.id,
          indifferent_params: @indifferent_params.merge(state: "closed")
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.rest_api_status_filter", "result:match"]).length
    end

    test "querying for all PRs returns no mismatches" do
      assert_nothing_raised do
        RestApiStatusFilterExperimentJob.perform_now(
          repository_id: @repo.id,
          user_id: @user.id,
          indifferent_params: @indifferent_params.merge(state: "all")
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.rest_api_status_filter", "result:match"]).length
    end

    test "querying without a 'state' arguments returns no mismatches" do
      assert_nothing_raised do
        RestApiStatusFilterExperimentJob.perform_now(
          repository_id: @repo.id,
          user_id: @user.id,
          indifferent_params: @indifferent_params
        )
      end

      assert_equal 1, GitHub.dogstats.increments("science", tags: ["experiment:pull_request.rest_api_status_filter", "result:match"]).length
    end
  end
end
