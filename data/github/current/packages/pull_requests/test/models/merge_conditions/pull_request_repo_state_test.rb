# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestRepoStateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
  end

  test "stateless methods" do
    merge_condition = MergeConditions::PullRequestRepoState.new(@pull, @owner, :merge)

    assert_equal "Pull request repository state", merge_condition.display_name
    assert_equal "The repository must be not archived or locked", merge_condition.description
  end

  test "fails when base repo is archived" do
    @repo.set_archived
    merge_condition = MergeConditions::PullRequestRepoState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestRepoState::FAILED_MESSAGE, merge_condition.message
  end

  test "fails when base repo is locked for migration" do
    @repo.lock!("moving")
    merge_condition = MergeConditions::PullRequestRepoState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
    assert_equal MergeConditions::PullRequestRepoState::FAILED_MESSAGE, merge_condition.message
  end

  test "passes when base repo is neither archived nor locked for migration" do
    refute @repo.locked?
    refute @repo.archived?

    merge_condition = MergeConditions::PullRequestRepoState.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
    assert_nil merge_condition.message
  end
end
