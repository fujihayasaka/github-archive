# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeStateRulesTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user)
    @org = create(:business_plus_organization, admin: @user)
    @repo = create(:private_repository, owner: @org, from_example: :pull_request_source)
    @repo.add_member(@user, action: :admin)

    @pull = PullRequest.create_for!(@repo,
      title: "Sample pull request",
      base: "master",
      head: "master-forward-2",
      user: @user)

    @ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: @pull.qualified_base_ref_name, source: @repo)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @pull.create_merge_commit
  end

  test "#status is :clean when squash merge only blocked by commit metadata rules (feature flag enabled)" do
    enable_feature_flag(:rulesets_prx_merge_improvements)

    create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: @ruleset)

    state = PullRequest::MergeState.new(@pull, viewer: @pull.user, merge_method: :squash)

    assert_equal :clean, state.status
  end

  test "#status is :blocked when squash merge blocked by non-commit metadata rules" do
    create(:repository_rule_configuration, :update, repository_ruleset: @ruleset)

    state = PullRequest::MergeState.new(@pull, viewer: @pull.user, merge_method: :squash)

    assert_equal :blocked, state.status
  end

  test "#status is :blocked when squash merge blocked by commit metadata and other rules" do
    create(:repository_rule_configuration, :update, repository_ruleset: @ruleset)
    create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: @ruleset)

    state = PullRequest::MergeState.new(@pull, viewer: @pull.user, merge_method: :squash)

    assert_equal :blocked, state.status
  end

  test "#status is :blocked when squash merge only blocked by commit metadata rules (feature flag disabled)" do
    disable_feature_flag(:rulesets_prx_merge_improvements)

    create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: @ruleset)

    state = PullRequest::MergeState.new(@pull, viewer: @pull.user, merge_method: :squash)

    assert_equal :blocked, state.status
  end

end
