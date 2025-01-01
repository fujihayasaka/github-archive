# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class MergeRequirementsTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @org = create :business_plus_organization
    @repo = create :repository, name: "theyre-good-repos-bront", owner: @org, from_example: :pull_request_fork
    @user = create :collaborator, login: "wampa", repository: @repo
    @primary_email = @user.emails.primary.first
    @primary_email.verify!
    @reviewer = create :collaborator, login: "reviewer", repository: @repo
    @reviewer_primary_email = @reviewer.emails.primary.first
    @reviewer_primary_email.verify!

    base_ref = @repo.heads.find_or_build("master")
    # This branch is needed for the deployment rule tests
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

    assert @pull.create_merge_commit

    @forker = create(:user)
    @forked_repo = create :fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork

    @forked_pull = create(:pull_request,
      repository:  @repo,
      base_repository:  @repo,
      base_user:  @repo.owner,
      base_ref:  "master",
      head_repository:  @forked_repo,
      head_user:  @forker,
      head_ref:  "topic-rebased-on-master"
    )
    assert @forked_pull.create_merge_commit
  end

  setup do
    @merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, nil, false, @user)
  end

  context "#state returns overall state of all the merge conditions" do
    test "returns unknown when pull request when mergeability is nil" do
      PullRequest.any_instance.stubs(:currently_mergeable?).returns(nil)

      assert_equal :unknown, @merge_requirements.state
    end

    test "returns merge requirements with mergeable state when clean" do
      PullRequest.any_instance.stubs(:currently_mergeable?).returns(true)

      assert_equal :mergeable, @merge_requirements.state
    end

    test "returns mergeable when rules are passing" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :pull_request, repository_ruleset: ruleset)

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

      assert_equal :mergeable, merge_requirements.state
    end

    test "returns mergeable_if_statuses_pass when skip_checks flag is TRUE and required checks are enabled/present" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :required_status_checks, repository_ruleset: ruleset)
      @pull.create_merge_commit

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user, skip_checks: true)

      assert_equal :mergeable_if_statuses_pass, merge_requirements.state
    end

    test "returns mergeable when skip_checks flag is TRUE and there are no required checks enabled/present" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :pull_request, repository_ruleset: ruleset)
      @pull.create_merge_commit

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user, skip_checks: true)

      assert_equal :mergeable, merge_requirements.state
    end

    test "returns unmergeable when rules are not passing" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)

      assert_equal :unmergeable, merge_requirements.state
      assert merge_requirements.conditions.filter { |c| c.result == :failed }.all? { |c| c.class == MergeConditions::PullRequestRules }
    end

    test "returns mergeable when only commit metadata rules fail for squash merges when feature flag enabled" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)
      @pull.create_merge_commit

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @user)

      if GitHub.flipper[:rulesets_prx_merge_improvements].enabled?
        assert_equal :mergeable, merge_requirements.state
      else
        assert_equal :unmergeable, merge_requirements.state
      end

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
      assert_equal :unmergeable, merge_requirements.state

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :rebase, false, @user)
      assert_equal :unmergeable, merge_requirements.state
    end

    test "returns unmergeable when non-commit metadata rules fail for squash merges" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :update, repository_ruleset: ruleset)
      create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)
      @pull.create_merge_commit

      merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @user)
      assert_equal :unmergeable, merge_requirements.state
    end
  end

  context "#default_commit_author_email returns possible commit author emails based on merge method" do
    if GitHub.choose_commit_email_enabled?
      context ":merge" do
        test "returns commit author email for the current viewer" do
          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @reviewer)
          assert_equal @reviewer.git_author_email, merge_requirements.default_commit_author_email
        end

        test "returns the commit author's private email address when keep email address private is enabled" do
          @user.primary_user_email.toggle_visibility
          refute @user.primary_user_email.public?

          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
          assert_equal @user.git_author_email, merge_requirements.default_commit_author_email
        end
      end
      context ":squash" do
        test "always returns the pull's author email" do
          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @reviewer)
          assert_equal @user.git_author_email, merge_requirements.default_commit_author_email
        end

        test "returns the commit author's private email address when keep email address private is enabled" do
          @user.primary_user_email.toggle_visibility
          refute @user.primary_user_email.public?

          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @user)
          assert_equal @user.git_author_email, merge_requirements.default_commit_author_email
        end
      end
    end
  end

  context "#possible_commit_author_emails returns possible commit author emails based on merge method" do
    if GitHub.choose_commit_email_enabled?
      context ":merge" do
        test "viewer has only one email" do
          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end

        test "viewer has more than one email" do
          second_email = @user.add_email "notifications@example.com"
          second_email.verify!
          @user.reload

          results = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @user).possible_commit_author_emails
          assert_includes results, @primary_email.email
          assert_includes results, second_email.email
        end

        test "viewer is not the author and has more than one email" do
          second_email = @reviewer.add_email "notifications@example.com"
          second_email.verify!
          @reviewer.reload

          results = PullRequest::MergeRequirements.new(@pull, nil, :merge, false, @reviewer).possible_commit_author_emails
          assert_includes results, @reviewer_primary_email.email
          assert_includes results, second_email.email
        end
      end

      context ":squash" do
        test "viewer has only one email" do
          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @user)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end

        test "viewer has more than one email" do
          second_email = @user.add_email "notifications@example.com"
          second_email.verify!
          @user.reload

          results = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @user).possible_commit_author_emails
          assert_includes results, @primary_email.email
          assert_includes results, second_email.email
        end

        test "viewer has more than one email and is not author" do
          second_email = @reviewer.add_email "notifications@example.com"
          second_email.verify!
          @reviewer.reload

          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :squash, false, @reviewer)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end
      end

      context ":rebase" do
        test "viewer has only one email" do
          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :rebase, false, @user)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end

        test "viewer has more than one email" do
          second_email = @user.add_email "notifications@example.com"
          second_email.verify!
          @user.reload

          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :rebase, false, @user)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end

        test "viewer has more than one email and is not author" do
          second_email = @reviewer.add_email "notifications@example.com"
          second_email.verify!
          @reviewer.reload

          merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, :rebase, false, @reviewer)
          assert_equal [], merge_requirements.possible_commit_author_emails
        end
      end
    end
  end

  test "returns merge requirements for a ghost user" do
    @pull.user = User.ghost
    @pull.save!
    assert_equal @pull.reload.user, User.ghost

    merge_requirements = PullRequest::MergeRequirements.new(@pull, nil, nil, false, User.ghost)
    assert_equal :unknown, merge_requirements.state
    assert_equal User.ghost.git_author_email, merge_requirements.default_commit_author_email
  end

  context "#merge_method" do
    test "returns specific merge method if merge_action is not :merge_queue" do
      merge_requirements = PullRequest::MergeRequirements.new(@pull, :direct_merge, :rebase, false, @pull.user)

      assert_equal :rebase, merge_requirements.merge_method.sync
    end

    test "returns specific merge method and can handle strings" do
      merge_requirements = PullRequest::MergeRequirements.new(@pull, :direct_merge, "rebase", false, @pull.user)

      assert_equal :rebase, merge_requirements.merge_method.sync
    end

    test "returns default merge method if merge_action is :merge_queue" do
      merge_requirements = PullRequest::MergeRequirements.new(@pull, :merge_queue, "rebase", false, @pull.user)
      default_merge_method = @repo.default_merge_method_for(@user)

      assert_equal default_merge_method, merge_requirements.merge_method.sync
    end
  end

  context "#merge_action" do
    test "returns specified merge action it even if it's not allowed" do
      merge_requirements = PullRequest::MergeRequirements.new(@pull, :merge_queue, :rebase, false, @pull.user)

      assert_equal :merge_queue, merge_requirements.merge_action.sync
    end

    test "returns the direct merge action if both direct merge and merge queue are blocked for the user" do
      merge_requirements = PullRequest::MergeRequirements.new(@forked_pull, nil, nil, false, @forker)

      refute @pull.merge_queue_enabled?
      refute @pull.repository.pushable_by?(@forker, ref: @pull.base_ref_name)
      assert_equal :unmergeable, merge_requirements.state
      assert_equal :direct_merge, merge_requirements.merge_action.sync
    end

    test "returns the merge queue action if both direct merge and merge queue are blocked for the user but the repo is configured for merge queue" do
      merge_requirements = PullRequest::MergeRequirements.new(@forked_pull, nil, nil, false, @forker)
      create(:merge_queue, repository: @repo, merge_method: "merge")

      assert @pull.merge_queue_enabled?
      refute @pull.repository.pushable_by?(@forker, ref: @pull.base_ref_name)
      assert_equal :unmergeable, merge_requirements.state
      assert_equal :merge_queue, merge_requirements.merge_action.sync
    end
  end


  test "returns no failing merge conflict conditions when mergeable" do
    PullRequest.any_instance.stubs(:currently_mergeable?).returns(true)

    assert_equal :mergeable, @merge_requirements.state
    merge_conflict_condition = @merge_requirements.conditions.detect { |c| c.class == MergeConditions::PullRequestMergeConflictState }
    assert merge_conflict_condition
    assert_equal :passed, merge_conflict_condition.result
    assert_nil merge_conflict_condition.condition_payload.conflicts
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
    assert_equal ["foo.txt"], merge_conflict_condition.condition_payload.conflicts
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
      pull_request_rule_condition = T.cast(pull_request_rule_condition, MergeConditions::PullRequestRules)
      rule_rollups = pull_request_rule_condition.condition_payload.ruleRollups
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
      pull_request_rule_condition = T.cast(pull_request_rule_condition, MergeConditions::PullRequestRules)
      rule_rollups = pull_request_rule_condition.condition_payload.ruleRollups
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
      pull_request_rule_condition = T.cast(pull_request_rule_condition, MergeConditions::PullRequestRules)
      rule_rollups = pull_request_rule_condition.condition_payload.ruleRollups
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
      pull_request_rule_condition = T.cast(pull_request_rule_condition, MergeConditions::PullRequestRules)
      rule_rollups = pull_request_rule_condition.condition_payload.ruleRollups
      update_rule_rollup = rule_rollups&.find { |r| r.ruleType.serialize == "UPDATE" }

      assert_nil(update_rule_rollup&.metadata)
    end
  end
end
