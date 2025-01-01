# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"

class PullRequests::Orchestrations::UpdateBranchTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @pull_request = create(:pull_request, :with_mergeable_head, user: @user, repository: @repo)
  end

  test "catches repo rules violations and returns a detailed message" do
    data = {
      user_id: @user.id, update_method: "merge", expected_head_oid: @pull_request.head_sha
    }

    PullRequest.any_instance.expects(:merge_base_into_head).raises(Git::Ref::RepositoryRuleViolationError.new(RuleEngine::RuleSuite.new))
    orchestration = PullRequests::Orchestrations::UpdateBranch.create(repository: @pull_request.repository, pull_request: @pull_request, data:)
    orchestration.execute!

    perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

    assert_predicate orchestration.reload, :failed?
    assert_equal "Repository rule violations found", orchestration.error_message
  end

  test "sets failure state on uncaught errors" do
    data = {
      user_id: @user.id, update_method: "merge", expected_head_oid: @pull_request.head_sha
    }

    PullRequest.any_instance.expects(:merge_base_into_head).raises(StandardError.new("generic uncaught error"))

    orchestration = PullRequests::Orchestrations::UpdateBranch.create(repository: @pull_request.repository, pull_request: @pull_request, data:)
    orchestration.execute!

    assert_raises(StandardError) do
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])
    end

    assert_predicate orchestration.reload, :failed?
    assert_equal "An unknown error occured. Please try again.", orchestration.error_message
  end
end
