# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestMergeMethodTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
    @rando = create(:user)
  end

  test "fails when repo doesn't allow merge and merge method is merge" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: false,
      squash_allowed: true,
      rebase_allowed: true,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
  end

  test "passes when repo allows merge and merge method is merge" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: true,
      squash_allowed: true,
      rebase_allowed: true,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :merge)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
  end

  test "fails when repo doesn't allow squash and merge method is squash" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: true,
      squash_allowed: false,
      rebase_allowed: true,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :squash)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
  end

  test "passes when repo allows squash and merge method is squash" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: true,
      squash_allowed: true,
      rebase_allowed: true,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :squash)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
  end

  test "fails when repo doesn't allow rebase and merge method is rebase" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: true,
      squash_allowed: true,
      rebase_allowed: false,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :rebase)
    merge_condition.async_evaluate.sync

    assert_equal :failed, merge_condition.result
  end

  test "passes when repo allows rebase and merge method is rebase" do
    @repo.update_merge_settings(@repo.owner,
      merge_allowed: true,
      squash_allowed: true,
      rebase_allowed: true,
    )

    merge_condition = MergeConditions::PullRequestMergeMethod.new(@pull, @owner, :rebase)
    merge_condition.async_evaluate.sync

    assert_equal :passed, merge_condition.result
  end
end
