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

  sig { params(action: PullRequest::AllowableMergeAction).returns(T::Hash[Symbol, T.untyped]) }
  def merge_action_to_h(action)
    { name: action.name, allowable_status: action.allowable_status }
  end

  test "when the merge queue is enabled, admins can bypass and direct merge", skip_enterprise: true do
    enable_feature_flag(:merge_queue)

    # has_merge_queue creates a protected branch that is bypassable by admins
    repo = create(:repository, :has_merge_queue, owner: @owner)

    pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @owner)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: @owner,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      allowable_status: :allowed
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :allowed_with_bypass
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "when the merge queue is enabled via rulesets, bypassers can bypass and direct merge", skip_enterprise: true do
    enable_feature_flag(:merge_queue)
    enable_feature_flag(:merge_action_mq_bypass)

    non_admin = create(:user)

    org = create(:organization, plan: "business_plus", admin: @owner)
    org.add_member(non_admin)
    team = create(:team, organization: org, privacy: :closed)
    team.add_member(non_admin)
    repo = create(:repository, owner: org, from_example: :pull_request_source)
    repo.add_member(non_admin)
    pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @owner)

    ruleset = create(:repository_ruleset, :targets_default_branch, source: repo, rule_configurations: [build(:repository_rule_configuration, :merge_queue)])
    create(:repository_ruleset_bypass_actor, repository_ruleset: ruleset, actor: team)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: pr,
      viewer: non_admin,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      allowable_status: :allowed
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :allowed_with_bypass
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "when the merge queue is enabled, non-admins cannot bypass", skip_enterprise: true do
    enable_feature_flag(:merge_queue)

    # has_merge_queue creates a protected branch that is bypassable by admins
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
      allowable_status: :allowed
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :blocked
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "when the merge queue is disabled, only direct_merge is allowed for admins" do
    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: @owner,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      allowable_status: :blocked
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :allowed
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  test "if the merge queue is disabled, allows only direct_merge for non-admins" do
    non_admin = create(:user)
    @repo.add_member(non_admin)

    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: non_admin,
    ).sync

    expected_merge_queue = {
      name: :merge_queue,
      allowable_status: :blocked
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :allowed
    }

    assert_equal [expected_merge_queue, expected_direct_merge], data.map { |action| merge_action_to_h(action) }
  end

  def empty_result
    expected_merge_queue = {
      name: :merge_queue,
      allowable_status: :blocked
    }

    expected_direct_merge = {
      name: :direct_merge,
      allowable_status: :blocked
    }

    [expected_merge_queue, expected_direct_merge]
  end

  test "allows nothing if the user does not have permissions to merge" do
    data = PullRequest::AllowableMergeAction.for(
      pull_request: @pr,
      viewer: @forker,
    ).sync

    assert_equal empty_result, data.map { |action| merge_action_to_h(action) }
  end
end
