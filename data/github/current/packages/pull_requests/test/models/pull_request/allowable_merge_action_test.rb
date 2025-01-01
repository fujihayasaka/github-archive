# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class AllowablePullRequestMergeActionTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @owner = create :user, login: "wampa", plan: "pro"
    @forker = create(:user, login: "forker")

    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)

    @pr = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      head_repository: @fork,
      head_ref: "topic",
      base_user: @repo.owner,
      base_ref: "master",
      head_user: @fork.owner,
      user: @forker)
  end

  def merge_action_to_h(action)
    { name: action.name, is_allowable: action.is_allowable, is_allowable_with_bypass: action.is_allowable_with_bypass }
  end

  test "when the merge queue is enabled, admins can bypass and direct merge", skip_enterprise: true do
    GitHub.flipper[:merge_queue].enable
    repo = create(:repository, :has_merge_queue, owner: @owner)

    pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @owner)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: @owner,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      is_allowable: true,
      is_allowable_with_bypass: false
    }

    expected_direct_merge = {
      name: :direct_merge,
      is_allowable: false,
      is_allowable_with_bypass: true
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "when the merge queue is enabled, non-admins cannot bypass", skip_enterprise: true do
    GitHub.flipper[:merge_queue].enable
    repo = create(:repository, :has_merge_queue, owner: @owner)

    pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @owner)

    non_admin = create(:user)
    repo.add_member(non_admin)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: non_admin,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      is_allowable: true,
      is_allowable_with_bypass: false
    }

    expected_direct_merge = {
      name: :direct_merge,
      is_allowable: false,
      is_allowable_with_bypass: false
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "when the merge queue is disabled, only direct_merge is is_allowable and admins can bypass" do

    # We need the protected branch for PullRequest#async_can_merge_as_admin? to work
    # correctly.
    protected_branch = @repo.protect_branch(
      @repo.default_branch,
      creator: @repo.owner,
      entry_point: :test_case
    )
    protected_branch.save!

    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: @owner,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      is_allowable: false,
      is_allowable_with_bypass: false
    }

    expected_direct_merge = {
      name: :direct_merge,
      is_allowable: true,
      is_allowable_with_bypass: true
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "if the merge queue is disabled, allows only direct_merge with no option to bypass for non-admins" do

    non_admin = create(:user)
    @repo.add_member(non_admin)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: non_admin,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      is_allowable: false,
      is_allowable_with_bypass: false
    }

    expected_direct_merge = {
      name: :direct_merge,
      is_allowable: true,
      is_allowable_with_bypass: false
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  def empty_result
    expected_merge_queue = {
      name: :merge_queue,
      is_allowable: false,
      is_allowable_with_bypass: false
    }

    expected_direct_merge = {
      name: :direct_merge,
      is_allowable: false,
      is_allowable_with_bypass: false
    }

    [expected_merge_queue, expected_direct_merge]
  end

  test "allows nothing if the pull request is a draft" do
    pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @owner, work_in_progress: true)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: @owner,
    ).sync

    assert_equal empty_result, data.map { |action| merge_action_to_h(action) }
  end

  test "allows nothing if the pull request is closed" do
    pr = create(:pull_request, :with_mergeable_head, :closed, repository: @repo, user: @owner)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: @owner,
    ).sync

    assert_equal empty_result, data.map { |action| merge_action_to_h(action) }
  end

  test "allows nothing if the user does not have permissions to merge" do
    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: @forker,
    ).sync

    assert_equal empty_result, data.map { |action| merge_action_to_h(action) }
  end
end
