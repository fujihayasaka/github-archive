# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeConditions::PullRequestMergeConflictStateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user, login: "forker", plan: "micro")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
    @fork_pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @fork,
      head_user: @fork.owner,
      head_ref: "topic",
      user: @forker
    )
    @collaborator = create(:collaborator, collaborator: create(:user), repository: @repo, action: :read)
  end

  context "evaluating the condition" do
    test "passes when pull request has no conflicts" do
      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
      merge_condition.async_evaluate.sync

      assert_equal :passed, merge_condition.result
      assert_nil merge_condition.message
    end

    test "fails when pull request has a merge conflict and merge_method is :merge" do
      create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
      merge_condition.async_evaluate.sync

      assert_equal :failed, merge_condition.result
      assert_equal "Pull request cannot be merged because it has a merge conflict.", merge_condition.message
    end

    test "passes when pull request has a rebase conflict and merge_method is :merge" do
      create_conflict(pull_request: @pull, conflict_type: :rebase_conflict, complex: false)

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
      merge_condition.async_evaluate.sync

      assert_equal :passed, merge_condition.result
      assert_nil merge_condition.message
    end

    test "fails when pull request has a rebase_conflict and merge_method is :rebase" do
      create_conflict(pull_request: @pull, conflict_type: :rebase_conflict, complex: false)

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
      merge_condition.async_evaluate.sync

      assert_equal :failed, merge_condition.result
      assert_equal "Pull request cannot be merged via rebase because it has a rebase conflict.", merge_condition.message
    end

    test "fails when pull request has a merge conflict and merge_method is :rebase" do
      create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
      merge_condition.async_evaluate.sync

      assert_equal :failed, merge_condition.result
      assert_equal "Pull request cannot be merged because it has a merge conflict.", merge_condition.message
    end

    test "calls enqueue_mergeable_update when skip_enqueue_mergable_update is disabled" do
      disable_feature_flag(:skip_enqueue_mergable_update)
      PullRequest.any_instance.expects(:enqueue_mergeable_update).at_least_once

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
      merge_condition.async_evaluate.sync
    end

    test "does not call enqueue_mergeable_update when skip_enqueue_mergable_update is enabled" do
      enable_feature_flag(:skip_enqueue_mergable_update)
      PullRequest.any_instance.expects(:enqueue_mergeable_update).times(0)

      merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :rebase)
      merge_condition.async_evaluate.sync
    end
  end

  context "#condition_payload" do
    context "web editor conflict resolution" do
      test "when there is no merge conflict" do
        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_nil web_editor_conflict_resolution
      end

      test "when the merge conflict can be resolved in the web editor" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert web_editor_conflict_resolution&.viewerCanResolve
        assert_nil web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_nil web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the cross repo merge conflict can be resolved on the web because the conflict editor is enabled" do
        create_conflict(pull_request: @fork_pull, conflict_type: :merge_conflict, complex: false)
        GitHub.stubs(:cross_repo_conflict_editor_enabled?).returns(true)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@fork_pull, @forker, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal true, web_editor_conflict_resolution&.viewerCanResolve
        assert_nil web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_nil web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the merge conflict is too complex to resolve in the web editor" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: true)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::TooComplex, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "These conflicts are too complex to resolve in the web editor.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the user cannot push AND the merge conflict is too complex to resolve in the web editor" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: true)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @collaborator, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::InsufficientAccess, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "You do not have permission to push to the head branch.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the user cannot push AND cross repo merge conflict cannot be resolved on the web because the conflict editor is disabled" do
        create_conflict(pull_request: @fork_pull, conflict_type: :merge_conflict, complex: false)
        GitHub.stubs(:cross_repo_conflict_editor_enabled?).returns(false)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@fork_pull, @collaborator, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::InsufficientAccess, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "You do not have permission to push to the head branch.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the cross repo merge conflict cannot be resolved on the web because the conflict editor is disabled" do
        create_conflict(pull_request: @fork_pull, conflict_type: :merge_conflict, complex: false)
        GitHub.stubs(:cross_repo_conflict_editor_enabled?).returns(false)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@fork_pull, @forker, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::AdminDisabled, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "Web conflict resolution across forked repositories has been disabled by your site administrator.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the merge conflict cannot be resolved on the web because the head branch is protected" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)
        branch = create(:protected_branch, repository: @repo, name: @pull.head_ref_name, lock_branch_enforcement_level: :everyone)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @owner, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::HeadBranchProtected, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "#{@pull.display_head_ref_name} is a protected branch.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the user cannot push to the branch AND merge conflict cannot be resolved on the web because the head branch is protected" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)
        branch = create(:protected_branch, repository: @repo, name: @pull.head_ref_name, lock_branch_enforcement_level: :everyone)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @collaborator, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::InsufficientAccess, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "You do not have permission to push to the head branch.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end

      test "when the merge conflict cannot be resolved on the web because the viewer cannot push to the head branch" do
        create_conflict(pull_request: @pull, conflict_type: :merge_conflict, complex: false)

        merge_condition = MergeConditions::PullRequestMergeConflictState.new(@pull, @collaborator, :merge)
        merge_condition.async_evaluate.sync
        web_editor_conflict_resolution = merge_condition.condition_payload.webEditorConflictResolution

        assert_equal false, web_editor_conflict_resolution&.viewerCanResolve
        assert_equal PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::InsufficientAccess, web_editor_conflict_resolution&.viewerCannotResolve&.reason
        assert_equal "You do not have permission to push to the head branch.", web_editor_conflict_resolution&.viewerCannotResolve&.message
      end
    end
  end

  def create_conflict(pull_request:, conflict_type:, complex:)
    if conflict_type == :rebase_conflict
      PullRequestConflict.create!(
        pull_request: pull_request,
        base_sha: pull_request.mergeable_base_sha,
        head_sha: pull_request.mergeable_head_sha,
        info: "{}",
        conflict_type: conflict_type,
      )
    else
      pull_request.store_conflicts({
        base: pull_request.mergeable_base_sha,
        head: pull_request.mergeable_head_sha,
        conflicted_files: {
          "example.txt" => { "type" => complex ? "not_regular_conflict" : "regular_conflict" },
        },
        conflict_type: conflict_type,
      })
    end
  end
end
