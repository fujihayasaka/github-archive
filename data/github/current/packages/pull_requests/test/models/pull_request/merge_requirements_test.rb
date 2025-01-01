# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class MergeRequirementsTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @repo = create :repository, name: "theyre-good-repos-bront"
    @user = create :collaborator, login: "wampa", repository: @repo
    @reviewer = create :collaborator, login: "reviewer", repository: @repo

    base_ref = @repo.heads.find_or_build("master")
    base_ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file001", "foo")
    end

    head_ref = @repo.heads.create("feature-branch", base_ref.target, @repo.owner)
    head_ref.append_commit({ message: "another change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file002", "foo")
    end

    issue = create(:issue, user: @user, repository: @repo)
    @pull  = create(:pull_request,
      repository:  @repo,
      base_repository:  @repo,
      base_user:  @repo.owner,
      base_ref:  "master",
      head_repository:  @repo,
      head_user:  @repo.owner,
      head_ref:  "feature-branch",
      issue:  issue,
    )

    @pull.create_merge_commit
  end

  setup do
    @merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, nil, false, @user)
  end

  test "returns merge requirements state for user" do
    assert_equal :unknown, @merge_requirements.state
  end

  test "returns commit author email" do
    assert_equal @user.git_author_email, @merge_requirements.commit_author
  end

  test "returns merge requirements for a ghost user" do
    @pull.user = User.ghost
    @pull.save!
    assert_equal @pull.reload.user, User.ghost

    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, nil, false, User.ghost)
    assert_equal :unknown, merge_requirements.state
    assert_equal User.ghost.git_author_email, merge_requirements.commit_author
  end

  test "returns merge requirements with mergeable state when clean" do
    PullRequest.any_instance.stubs(:currently_mergeable?).returns(true)

    assert_equal :mergeable, @merge_requirements.state
  end

  test "returns no failing merge conflict conditions when mergeable" do
    PullRequest.any_instance.stubs(:currently_mergeable?).returns(true)

    assert_equal :mergeable, @merge_requirements.state
    merge_conflict_condition = @merge_requirements.conditions.detect { |c| c.class == MergeConditions::PullRequestMergeConflictState }
    assert merge_conflict_condition
    assert_equal :passed, merge_conflict_condition.result
    ## TODO: the serializer needs to render the list of merge conflicts but that's not exposed directly in this model
  end

  test "returns merge conflict condition when there are merge conflicts" do
    # create our merge conflict
    with_enqueued_pr_sync_jobs do
      create(:commit, repository: @pull.base_repository, branch: @pull.base_ref, changes: -> (files) { files.add("foo.txt", "contents of foo base") })
      create(:commit, repository: @pull.head_repository, branch: @pull.head_ref, changes: -> (files) { files.add("foo.txt", "contents of foo head") })
    end
    @pull.reload
    @pull.create_merge_commit
    refute_nil(@pull.conflict)

    assert_equal :unmergeable, @merge_requirements.state
    merge_conflict_condition = @merge_requirements.conditions.detect { |c| c.class == MergeConditions::PullRequestMergeConflictState }
    assert merge_conflict_condition
    assert_equal :failed, merge_conflict_condition.result
    ## TODO: the serializer needs to render the list of merge conflicts but that's not exposed directly in this model
  end

  test "returns the commit message headline and the commit message body" do
    expected_commit_message_headline = "Merge pull request ##{@pull.number} from #{@pull.head_user.display_login}/#{@pull.head_ref}"
    expected_commit_message_body = @pull.title

    assert_equal expected_commit_message_headline, @merge_requirements.commit_message_headline
    assert_equal expected_commit_message_body, @merge_requirements.commit_message_body
  end

  test "returns the commit message headline and commit message body when a merge method is passed in" do
    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

    expected_commit_message_headline = "Merge pull request ##{@pull.number} from #{@pull.head_user.display_login}/#{@pull.head_ref}"
    expected_commit_message_body = @pull.title

    assert_equal expected_commit_message_headline, merge_requirements.commit_message_headline
    assert_equal expected_commit_message_body, merge_requirements.commit_message_body
  end

  test "returns failing when rules are not passing" do
    ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
    create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

    assert_equal :unmergeable, merge_requirements.state
    assert merge_requirements.conditions.filter { |c| c.result == :failed }.all? { |c| c.class == MergeConditions::PullRequestRules }
  end

  test "returns mergable when rules are passing" do
    ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
    create(:repository_rule_configuration, :pull_request, repository_ruleset: ruleset)

    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

    assert_equal :mergeable, merge_requirements.state
  end

  test "returns passing allowed merge method condition when merge queue is enabled with a user who has merge rights" do
    create(:merge_queue, repository: @repo, merge_method: "merge")
    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
    condition = merge_requirements.conditions.find { |c| c.class == MergeConditions::PullRequestMergeMethod }

    assert_equal :passed, T.must(condition).result
  end

  context "rule metadata payloads" do
    test "returns the correct metadata for the pull request rule" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :pull_request, required_approving_review_count: 2, repository_ruleset: ruleset)

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
      pull_request_rule_condition = merge_requirements.conditions.find { |c| c.class == MergeConditions::PullRequestRules }
      rule_rollups = pull_request_rule_condition&.condition_payload&.ruleRollups
      pull_request_rule_rollup = rule_rollups&.find { |r| r.ruleType.serialize == "PULL_REQUEST" }
      metadata = T.cast(pull_request_rule_rollup&.metadata, RulesEngine::RuleRollups::PullRequestRollupMetadata::Payload)

      assert_equal ["more_reviews_required"], metadata.failureReasons
      assert_equal 2, metadata.requiredReviewers
      refute metadata.requiresCodeowners
    end

    test "returns the correct metadata for the required status check rule" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :required_status_checks, repository_ruleset: ruleset)
      @pull.create_merge_commit

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
      pull_request_rule_condition = merge_requirements.conditions.find { |c| c.class == MergeConditions::PullRequestRules }
      rule_rollups = pull_request_rule_condition&.condition_payload&.ruleRollups
      status_check_rule_rollup = rule_rollups&.find { |r| r.ruleType.serialize == "REQUIRED_STATUS_CHECKS" }
      metadata = T.cast(status_check_rule_rollup&.metadata, RulesEngine::RuleRollups::RequiredStatusCheckRollupMetadata::Payload)

      assert_equal [
        RulesEngine::RuleRollups::StatusCheckResult::Payload.new(
        context: "build",
        integrationId: nil,
        result: "expected",
      ),
       RulesEngine::RuleRollups::StatusCheckResult::Payload.new(
        context: "test",
        integrationId: nil,
        result: "expected"
      ),
       RulesEngine::RuleRollups::StatusCheckResult::Payload.new(
        context: "lint",
        integrationId: nil,
        result: "expected"
      )].as_json, metadata.statusCheckResults.as_json
    end

    test "returns the correct metadata for the required deployments rule" do
      @repo.deployments.create!(environment: "missing", creator: @user, sha: @pull.base_sha)
      @repo.deployments.create!(environment: "success", creator: @user, sha: @pull.head_sha)

      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/#{@pull.base_ref_name}", source: @repo)
      create(:repository_rule_configuration, :required_deployments, environments: %w[success missing], repository_ruleset: ruleset)

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

      pull_request_rule_condition = merge_requirements.conditions.find { |c| c.class == MergeConditions::PullRequestRules }
      rule_rollups = pull_request_rule_condition&.condition_payload&.ruleRollups
      deployments_rule_rollup = rule_rollups&.find { |r| r.ruleType.serialize == "REQUIRED_DEPLOYMENTS" }
      metadata = T.cast(deployments_rule_rollup&.metadata, RulesEngine::RuleRollups::RequiredDeploymentRollupMetadata::Payload)

      assert_equal ["success"], metadata.deployedEnvironments
      assert_equal ["missing"], metadata.missingEnvironments
    end

    test "returns no metadata for other rules" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

      pull_request_rule_condition = merge_requirements.conditions.find { |c| c.class == MergeConditions::PullRequestRules }
      rule_rollups = pull_request_rule_condition&.condition_payload&.ruleRollups
      update_rule_rollup = rule_rollups&.find { |r| r.ruleType.serialize == "UPDATE" }

      assert_nil(update_rule_rollup&.metadata)
    end
  end
end
