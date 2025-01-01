# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestStateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
  end

  test "stateless methods" do
    merge_condition = MergeConditions::PullRequestState.new(@pull, @owner, :merge)

    assert_equal "Pull request state", merge_condition.display_name
    assert_equal "Pull request must be open and not in draft mode in order to be merged", merge_condition.description
  end

  test "fails when pull request is in draft state" do
    @pull.update!(draft: true)
    merge_condition = MergeConditions::PullRequestState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestState::FAILED_MESSAGE, merge_condition.message
  end

  test "fails when pull request is closed" do
    @pull.close(@owner)

    merge_condition = MergeConditions::PullRequestState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestState::FAILED_MESSAGE, merge_condition.message
  end

  test "fails when pull request is merged" do
    pull = create(:pull_request, :with_mergeable_head, repository: @repo)
    pull.merge(@owner)
    pull.reload
    assert pull.merged?

    merge_condition = MergeConditions::PullRequestState.new(pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestState::FAILED_MESSAGE, merge_condition.message
  end

  if GitHub.merge_queues_enabled?
    test "fails when pull request is in the merge queue" do
      repo = create(:repository, :has_merge_queue, owner: @owner)
      pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @owner)
      queue = repo.default_merge_queue
      queue.enqueue!(pull_request: pr, enqueuer: @owner)

      merge_condition = MergeConditions::PullRequestState.new(pr, @owner, :merge)
      merge_condition.async_evaluate.sync

      assert_equal :failed, merge_condition.result
      assert_equal MergeConditions::PullRequestState::FAILED_MESSAGE, merge_condition.message
    end
  end

  test "passes when pull request is open, not in draft, and not in the merge queue" do
    assert @pull.open?
    refute @pull.draft?
    refute @pull.in_merge_queue?

    merge_condition = MergeConditions::PullRequestState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
    assert_nil merge_condition.message
  end
end
