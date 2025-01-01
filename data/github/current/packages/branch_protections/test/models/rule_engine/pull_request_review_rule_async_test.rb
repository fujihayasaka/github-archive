# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewRuleAsyncTest < GitHub::TestCase
  include CommitTestHelper
  include RulesEngine::RefUpdateTestHelper
  include PullRequestSynchronizationTestHelpers
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "owner", plan: "micro")
    @user = create(:user, login: "pr-creator")
    @reviewer = create(:user, login: "reviewer")
    @another_reviewer = create(:user, login: "another-reviewer")
    @read_only_user = create(:user, login: "read-only-user")
    @forker = create(:user, login: "forker")

    @source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)

    @source.add_member @read_only_user, action: :read
    @source.add_member @reviewer, action: :write
    @source.add_member @another_reviewer, action: :write
    @source.add_member @forker, action: :write
    @source.add_member @user, action: :write

    @fork, msg = @source.fork(forker: @forker)
    assert @fork, "forking #{@source} as #{@forker} failed: #{msg.inspect}"

    example_repo :pull_request_fork,   @fork

    @protected_branch = create(:protected_branch, repository: @source, creator: @user,
      pull_request_reviews_enforcement_level: :everyone,
      required_status_checks_enforcement_level: :non_admins)

    @org = create(:organization)
    @org_admin = @org.admins.first
    @org_repo = create(:repository, owner: @org, from_example: :simple)
    @team = create(:team, organization: @org, privacy: :closed)
    @sub_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
    @team_member = create(:user)
    @sub_team_member = create(:user)
    @team.add_member(@team_member)
    @team.add_repository(@org_repo, :push)
    @sub_team.add_member(@sub_team_member)
    @org_protected_branch = create(:protected_branch, repository: @org_repo, creator: @user,
      pull_request_reviews_enforcement_level: :everyone,
      required_status_checks_enforcement_level: :non_admins
    )

    @compliance_team_1 = create(:team, organization: @org, privacy: :closed, name: "example-reviewers")
    @compliance_team_1_member = create(:user)
    @compliance_team_1.add_member(@compliance_team_1_member)
    @compliance_team_1.add_repository(@org_repo, :push)
    @compliance_team_2 = create(:team, organization: @org, privacy: :closed, name: "compliance-reviewers")
    @compliance_team_2_member = create(:user)
    @compliance_team_2.add_member(@compliance_team_2_member)
    @compliance_team_2.add_repository(@org_repo, :push)

    example_repo_snapshot

    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "master-forward-2",
      user: @user,
      title: "convert to CR line ending",
      body: "most valuable PR ever A++++ please do merge",
    )

    @cross_repo_pull = PullRequest.create_for!(@source,
      base: "owner:master",
      head: "forker:topic",
      user: @reviewer,
      title: "cross repo PR: merging forker:topic into master",
      body: "cross repo pull request",
    )

    @cr_line_endings_tip = @source.heads["master-forward-2"].target_oid

    @org_pull = PullRequest.create_for!(@org_repo,
      user:  @org_admin,
      base:  "master",
      head:  "cr-line-endings",
      title: "org pull title",
      body:  "org pull body",
    )
  end

  setup do
    example_repo_restore
  end

  # If empty, don't add content to commit
  def commit_and_push(ref, metadata: { message: "a commit", committer: @user }, author: @user, empty: false, pushed_at: Time.now)
    freeze_time do
      before = ref.target_oid
      after = ref.append_commit(metadata, author) do |files|
        if block_given?
          yield files
        elsif !empty
          files.add("file.txt", <<~TEXT
                        hello world!
                        TEXT
          )
        end
      end
      with_enqueued_pr_sync_jobs do
        trigger_push_event(
          ref.repository.shard_path,
          author.login,
          [["refs/heads/#{ref.name}", before, after.sha]],
          pushed_at,
        )
      end
    end
  end

  context "when the protected branch name contains a pattern rule" do
    test "denies when there are no PullRequestReviews" do
      @protected_branch.update!(name: "ma*")

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
    end
  end

  context "check for pull request" do
    test "denies when there are no PullRequestReviews" do
      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      refute_predicate decision, :code_owner_review_required?
    end

    test "denies when there are no PullRequestReviews async" do
      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      refute_predicate decision, :code_owner_review_required?
    end

    test "denies when there are only reviews from users who aren't writers" do
      review = @pull.reviews.create!(head_sha: "xxxxx", user: @read_only_user)
      review.approve!
      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      refute_predicate decision, :code_owner_review_required?
    end

    test "denies when there are only pending PullRequestReviews" do
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer)
      review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user)

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      reason = decision.reason
      assert_equal :review_policy_not_satisfied, reason.code
      assert_equal "Review required", reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", reason.message
    end

    test "passes when there is at least one approval from a user other than the PR author" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
      review1.approve!
      refute_equal @reviewer, @pull.user

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes for closed PR when there is at least one approval from a user other than the PR author" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
      review1.approve!
      refute_equal @reviewer, @pull.user

      @pull.close

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes for 1 open 1 closed PR when there is at least one approval from a user other than the PR author with multiple prs" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
      review1.approve!
      refute_equal @reviewer, @pull.user

      review2 = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user)
      refute_equal @user, @cross_repo_pull.user

      @pull.close

      decision1 = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision
      decision2 = @cross_repo_pull.merge_state(viewer: @reviewer).async_pull_request_review_policy_decision
      decision1, decision2 = Promise.all([decision1, decision2]).sync
      assert_predicate decision1, :rules_fulfilled?
      assert_predicate decision2, :more_reviews_required?
    end


    test "passes for open PRs when there is at least one approval from a user other than the PR author with multiple prs" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
      review1.approve!
      refute_equal @reviewer, @pull.user

      review2 = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user)
      refute_equal @user, @cross_repo_pull.user

      decision1 = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision
      decision2 = @cross_repo_pull.merge_state(viewer: @reviewer).async_pull_request_review_policy_decision
      decision1, decision2 = Promise.all([decision1, decision2]).sync
      assert_predicate decision1, :rules_fulfilled?
      assert_predicate decision2, :more_reviews_required?
    end

    test "denies when there is one approval and more than one are required" do
      @protected_branch.update!(required_approving_review_count: 2)

      @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
      refute_equal @reviewer, @pull.user

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?

      reason = decision.reason
      assert_equal :review_policy_not_satisfied, reason.code
      assert_equal "Review required", reason.summary
      assert_equal "At least 2 approving reviews are required by reviewers with write access.", reason.message
      assert_predicate decision, :more_reviews_required?
    end

    test "passes when there are two approvals and two are required" do
      @protected_branch.update!(required_approving_review_count: 2)

      @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
      refute_equal @reviewer, @pull.user
      @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
      refute_equal @another_reviewer, @pull.user

      decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      assert_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
      refute_predicate decision, :changes_requested?
    end

    context "approval_count=required_count but one of the approvers has pushed to the PR branch after it was opened when this is disallowed" do
      test "rejects when feature flag is on" do
        enable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        another_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # @reviewer commits to the PR branch, disqualifying their earlier review
        with_enqueued_pr_sync_jobs do
          @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @reviewer }, @reviewer)
        end

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 2 approving reviews are required by reviewers with write access who have not pushed changes to this pull request after it was opened. 1 review from 'reviewer' was disqualified because of a subsequent push.", decision.reason.message
        assert_equal [disqualified_review.id], decision.instrumentation_payload[:disqualified_review_ids]

        # adding an extra scenario inline where *both* reviews are disqualified
        # to check that grammar is ok.
        with_enqueued_pr_sync_jobs do
          # @another_reviewer commits to the PR branch, disqualifying their earlier review
          @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer)
        end

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 2 approving reviews are required by reviewers with write access who have not pushed changes to this pull request after it was opened. 2 reviews from 'another-reviewer' and 'reviewer' were disqualified because of a subsequent push.", decision.reason.message
        assert_same_elements [disqualified_review.id, another_review.id], decision.instrumentation_payload[:disqualified_review_ids]
      end

      test "accepts when ignore_approvals_from_contributors config is disabled" do
        enable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: false)

        @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # @reviewer commits to the PR branch
        perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
          @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @reviewer }, @reviewer)
        end

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when disqualify approvals from contributors is enabled" do
      test "rejects when approved by someone on a fork-specific branch who contributed after the PR was opened" do
        enable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, ignore_approvals_from_contributors: true)

        assert !@source.refs.map(&:name).include?(@cross_repo_pull.head_ref)
        # @reviewer commits to the PR branch
        # freeze time to ensure push comes before reviews
        freeze_time do
          perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
            perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
              @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @fork.owner }, @fork.owner)
            end
          end
        end
        # Ensure that the review comes after the push
        travel 1.minute
        # fork owner's approval doesnt count because they contributed after the PR was opened
        review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @fork.owner).tap(&:approve!)
        decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message

        # @user approves
        review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
        decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=0" do
      test "rejects without approvals" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        # Unapproved change by reviewer does not satisfy the policy
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

        travel 1.minute

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_predicate decision, :last_push_approval_required?
        message = if GitHub.flipper[:find_last_push_without_approvals].enabled?
          "New changes require approval from someone other than #{@reviewer.display_login} because they were the last pusher."
        else
          "New changes require approval from someone other than the last pusher."
        end
        assert_equal message, decision.reason.message
      end

      test "rejects when the last pusher is the only approver" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

        travel 1.minute

        review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_predicate decision, :last_push_approval_required?
        message = if GitHub.flipper[:find_last_push_without_approvals].enabled?
          "New changes require approval from someone other than #{@reviewer.display_login} because they were the last pusher."
        else
          "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes."
        end
        assert_equal message, decision.reason.message

        review2 = @pull.reviews.create(head_sha:  @pull.head_sha, user: @source.owner).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
        refute_predicate decision, :last_push_approval_required?
      end

      test "accepts when someone other than the last pusher approves" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

        travel 1.minute

        review1 = @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @source.owner).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
        refute_predicate decision, :last_push_approval_required?
      end
    end

    context "approval_count=required_count but the last pusher to push after the PR was opened approves the PR" do
      context "when require last push approval is enabled" do
        test "accepts the approval but requires more reviews when approval is required for the last push" do
          disable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          # Unapproved change by reviewer does not satisfy the policy

          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer, pushed_at: 1.day.ago)

          last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
          assert_equal(last_push.pusher_id, @reviewer.id)

          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          message = if GitHub.flipper[:find_last_push_without_approvals].enabled?
            "New changes require approval from someone other than #{@reviewer.display_login} because they were the last pusher."
          else
            "New changes require approval from someone other than the last pusher."
          end
          assert_equal message, decision.reason.message

          # reviewer approves, but this does not satisfy the policy since they pushed to the branch last
          review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_equal :approved, PullRequestReview.state_name(review1.state)
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than #{@reviewer.display_login} because they were the last pusher.", decision.reason.message

          # another_reviewer approves satisfying the policy
          review2 = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?

          # another_review pushes a change disqualifying their approval
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @another_reviewer },  author: @another_reviewer) do |files|
            files.add("another-file.txt", "new content")
          end

          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "Waiting on 1 reapproval from someone other than #{@another_reviewer.display_login} because they were the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
          end

          # reviewer re-approves after the push, satisfying the policy
          review3 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
          assert_equal(1, PullRequestReview.where(repository_id: @source.id, id: review3.id).update_all(submitted_at: 1.day.from_now))
          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end

        test "Handles missing pusher" do
          disable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          pusher = create :user
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: pusher, pushed_at: 1.day.ago)
          pusher.destroy!

          last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
          assert_nil(last_push.pusher)

          # Unapproved change by reviewer does not satisfy the policy
          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message

          # the review is after the push, and it satisfies the policy
          review2 = @pull.reviews.create(head_sha: @pull.reload.head_sha, user: @reviewer).tap(&:approve!)
          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end
      end

      context "when require last push approval is disabled" do
        test "accepts the approval and the review" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: false)
          @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          # @reviewer commits to the PR branch
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

          decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end
      end
    end

    context "approval_count=required_count but the last pusher to push before the PR was opened approves the PR" do
      test "accepts the approval but requires additional reviews to merge" do
        # This test asserts that if the last pusher to a branch before PR also approves the PR,
        # that it still requires additional reviews to satisfy the PR
        disable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        # @reviewer commits to the PR branch
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer, pushed_at: 1.day.ago)

        # manipulate things so the push is before the PR open
        last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
        assert_equal(last_push.pusher_id, @reviewer.id)

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        # Someone other than the last pusher can approve the PR
        another_review = @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert another_review.approved?
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count and ignore approvals from contributors and requiring approval for the last push are both enabled" do
      test "defers to the stricter ignore approvals policy" do
        enable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        another_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        decision = @pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # @reviewer commits to the PR branch, disqualifying their earlier review
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 2 approving reviews are required by reviewers with write access who have not pushed changes to this pull request after it was opened. 1 review from 'reviewer' was disqualified because of a subsequent push.", decision.reason.message
        assert_equal [disqualified_review.id], decision.instrumentation_payload[:disqualified_review_ids]
      end
    end

    context "approval_count=required_count but one of the approvers has pushed to the PR branch before it was opened" do
      test "accepts when ignore_approvals_from_contributors config is enabled" do
        # This test asserts that pushes to a PR branch before it was opened do not disqualify a user as an approver
        enable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # @reviewer commits to the PR branch
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer, pushed_at: 1.day.ago)

        # manipulate things so the push is before the PR open
        last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
        assert_equal(last_push.pusher_id, @reviewer.id)

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count but the last pusher to a fork-specific branch approves the PR" do
      context "when the push came before the PR" do
        test "accept the approval but requires additional reviews" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @fork.add_member @user, action: :write
          @fork.add_member @another_reviewer, action: :write

          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          # @another_reviewer commits to the PR branch before PR is opened
          travel(-1.day) do
            with_enqueued_pr_sync_jobs do
              @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer) do |files|
                files.add "file.txt", "Some content"
              end
            end
          end

          # @another_reviewer's approval is accepted, but still require additional approval
          @cross_repo_pull.reload.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than #{@another_reviewer.display_login} because they were the last pusher.", decision.reason.message

          @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
          @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end
      end

      context "when the push comes after the PR" do
        test "accept the approval but requires additional reviews" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @fork.add_member @user, action: :write
          @fork.add_member @another_reviewer, action: :write

          # @reviewer commits to the PR branch
          # freeze time to ensure push comes before reviews
          commit_and_push(@fork.refs.find(@cross_repo_pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

          # Ensure that the review comes after the push
          travel 1.minute
          # Review is accepted
          review = @cross_repo_pull.reload.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?

          # Ensure that the push comes after the review
          travel 1.minute

          # @another_reviewer commits to the PR branch, previous review is ignored
          commit_and_push(@fork.refs.find(@cross_repo_pull.head_ref), metadata: { message: "a commit", committer: @another_reviewer },  author: @another_reviewer) do |files|
            files.add("another-file.txt", "text")
          end

          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "New changes require approval from someone other than #{@another_reviewer.display_login} because they were the last pusher.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@another_reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          end

          # Ensure that the review comes after the push
          travel 1.minute
          # @another_reviewer's attempts to approve again, but we still require additional approval
          review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than #{@another_reviewer.display_login} because they were the last pusher.", decision.reason.message

          # Ensure that the review comes after the push
          travel 1.minute
          review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end
      end

      test "rejects when there is no head repository" do
        # Repositories can be deleted, which won't delete the associated PRs/reviews
        disable_feature_flag(:disqualify_pr_pushers_from_approving, @protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer },  author: @reviewer)

        @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        @pull.head_repository = nil
        @pull.save!(validate: false)

        decision = @pull.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert @pull.head_repository.nil?
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        # when we don't know the last pusher, we require 2 approvals
        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "Waiting on 2 reapprovals from reviewers with write access because the last pusher could not be determined. Review from #{@another_reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@another_reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end
    end
  end

  context "last pusher rule only for user pushes" do
    # A system-generated commit happens when a user presses "Update Branch" on a PR
    # We only want to compare commits from user pushes
    context "when there's a system-generated merge" do
      test "the PR does not require additional approvals" do
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # Changes are approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # Merge base into head
        topic_pr.reload.create_merge_commit
        with_enqueued_pr_sync_jobs do
          topic_pr.merge_base_into_head(
            user: @user,
            author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        # Still approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when system-generated rebase" do
      test "the PR does not require additional approvals" do
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # Changes are approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # Rebase
        topic_pr.reload.create_merge_commit
        with_enqueued_pr_sync_jobs do
          topic_pr.rebase_head_on_base(
            user: @user,
            author_email: @user.default_author_email(@source, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        # Still approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when a user pushes a commit without content" do
      test "the PR does not require additional approvals" do
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # Changes are approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # User pushes no content
        commit_and_push(@source.reload.refs.find("topic"), empty: true)

        # Still approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when there's a user push followed by a system-generated commit" do
      test "the PR requires additional approvals" do
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # Changes are approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # Merge base into head
        topic_pr.reload.create_merge_commit
        perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
          topic_pr.merge_base_into_head(
            user: @user,
            author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        # User pushes another change
        commit_and_push(@source.reload.refs.find("topic")) do |files|
          files.add("new-new-file.txt", <<~TEXT
            NEW hello world!
            TEXT
          )
        end

        # Another approval is required
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
      end
    end

    context "When there's a system-generated commit followed by a user push" do
      test "the PR requires additional approvals" do
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # Changes are approved
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # User pushes another change
        commit_and_push(@source.reload.refs.find("topic")) do |files|
          files.add("new-new-file.txt", <<~TEXT
            NEW hello world!
            TEXT
          )
        end

        # Merge base into head
        topic_pr.reload.create_merge_commit
        perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
          topic_pr.merge_base_into_head(
            user: @user,
            author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        # Another approval is required
        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
      end
    end

    context "when there is no PR" do
      test "the PR does not require additonal approvals if previously approved" do
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)

        # User pushes changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        topic_pr = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_pr.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!
        travel 1.day

        # User pushes changes to development
        commit_and_push(@source.refs.find("development")) do |files|
          files.add("README.md", <<~TEXT
            # This is a README
            TEXT
          )
        end
        travel 1.day

        # add protection to development
        protection = create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        decision = topic_pr.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # Merge base into head
        topic_pr.create_merge_commit
        with_enqueued_pr_sync_jobs do
          topic_pr.merge_base_into_head(
            user: @user,
            author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        ref_update = create_branch_update(
          @source,
          name: "development",
          before_oid: @source.reload.heads["development"].target_oid,
          after_oid: topic_pr.reload.head_sha)

        # Check the PR without the PR object
        decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/development" => protection }, actor: @user).first
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "PRs with different bases and the same head" do
      test "maintains approval only for PR with system-generated commit" do
        # When multiple prs with different bases and the same head,
        # only the PR where the update is made should still be approved
        enable_feature_flag(:last_reviewable_commit, @source)
        @source.heads.create("development", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("topic", @source.heads.find("master").commit.oid, @user)
        @source.heads.create("attack", @source.heads.find("master").commit.oid, @user)
        only = [PullRequestSynchronizationJob, SynchronizePullRequestJob]
        # push changes to topic
        commit_and_push(@source.refs.find("topic")) do |files|
          files.add("new-file.txt", <<~TEXT
            hello world!
            TEXT
          )
        end
        travel 1.day

        # pr from topic to dev
        topic_to_dev = PullRequest.create_for!(@source,
          base: "development",
          head: "topic",
          user: @user,
          title: "topic to dev",
          body: "a normal pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("topic").commit
        review = topic_to_dev.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!

        # push changes to attack
        commit_and_push(@source.reload.refs.find("attack")) do |files|
          files.add("a-totally-normal-file.txt", <<~TEXT
            a regular change
            TEXT
          )
        end
        travel 1.day

        # pr from topic to attack
        topic_to_attack = PullRequest.create_for!(@source,
          base: "attack",
          head: "topic",
          user: @user,
          title: "topic to attack",
          body: "an evil pr"
        )

        # Reviewer approves
        commit = @source.reload.refs.find("attack").commit
        review = topic_to_attack.reviews.create!(head_sha: commit.oid, user: @reviewer)
        review.approve!

        # push changes to development
        commit_and_push(@source.reload.refs.find("development")) do |files|
          files.add("dev.txt", <<~TEXT
            some text on dev
            TEXT
          )
        end
        travel 1.day

        # Push evil changes to attack AFTER approval
        commit_and_push(@source.reload.refs.find(topic_to_attack.base_ref)) do |files|
          files.add("evil-code.txt", <<~TEXT
            EVIL
            TEXT
          )
        end

        # Merge changes from base (attack) to head (topic)
        prev_head = topic_to_attack.reload.head_sha
        topic_to_attack.create_merge_commit
        freeze_time do
          with_enqueued_pr_sync_jobs do
            topic_to_attack.reload.merge_base_into_head(
              user: @user,
              author_email: @user.default_author_email(@source, topic_to_attack.head_sha),
              expected_head_oid: topic_to_attack.head_sha,
            )
          end
        end
        refute_equal prev_head, topic_to_attack.reload.head_sha

        # add protection to development
        create(
          :protected_branch,
          name: "development",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # add protection to topic
        create(
          :protected_branch,
          name: "topic",
          repository: @source,
          creator: @user,
          pull_request_reviews_enforcement_level: :everyone,
          required_approving_review_count: 1,
          require_last_push_approval: true
        )

        # topic_to_attack should still be approved
        decision = topic_to_attack.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # topic_to_development should not be approved
        decision = topic_to_dev.reload.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
      end
    end
  end

  context "code owners enforcement" do
    test "doesn't deny when waiting on code owner review when setting isn't enforced" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a
      @protected_branch.reload
      @protected_branch.update!(require_code_owner_review: false)

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?
      refute_predicate decision, :code_owner_review_required?
    end

    test "denies when waiting on required code owner reviews" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker and/or pr-creator.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      assert_predicate decision, :code_owner_review_required?
    end

    test "denies when codeowners review requests haven't been created" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a
      # We want to ensure the codeowners policy is enforced regardless of whether
      # review requests are created, since these will be created asynchronously.
      assert_empty @cross_repo_pull.review_requests, "review requests should not exist for this test case"

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker and/or pr-creator.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      assert_predicate decision, :code_owner_review_required?
    end

    test "denies when codeowners can't be determined" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      @cross_repo_pull.expects(:codeowners!).once.raises(PullRequest::DetermineCodeownersError.new(nil))

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Could not determine code owners from the current diff.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      assert_predicate decision, :code_owner_review_required?
    end

    test "requires each owned path to be reviewed" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @forker)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "only requires one owner review per owned path" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker and/or pr-creator.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "requires team member for team-owned path" do
      commit_codeowners(@org_pull, <<~CODEOWNERS)
        *   @#{@team.combined_slug}
      CODEOWNERS

      assert_same_elements [@team], @org_pull.codeowners.to_a

      decision = @org_pull.merge_state(viewer: @org_admin).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from #{@team.combined_slug}.", decision.reason.message

      review = @org_pull.reviews.create!(head_sha: @org_pull.head_sha, user: @team_member)
      review.approve!
      @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @org_pull.merge_state(viewer: @org_admin).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "allows sub-team member for team-owned path" do
      commit_codeowners(@org_pull, <<~CODEOWNERS)
        *   @#{@team.combined_slug}
      CODEOWNERS

      assert_same_elements [@team], @org_pull.codeowners.to_a

      decision = @org_pull.merge_state(viewer: @org_admin).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from #{@team.combined_slug}.", decision.reason.message

      review = @org_pull.reviews.create!(head_sha: @org_pull.head_sha, user: @sub_team_member)
      review.approve!
      @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @org_pull.merge_state(viewer: @org_admin).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end

    test "doesn't block if the PR author is the only code owner in the context of a PR" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @#{@cross_repo_pull.user}
      CODEOWNERS

      assert_same_elements [@cross_repo_pull.user], @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
    end


    test "blocks when checking outside of the context of a PR" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator
        file18   @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a

      merge_commit_oid = @cross_repo_pull.create_merge_commit
      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)

      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch.reload }, actor: @owner).first

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker and/or pr-creator.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user)
      review.approve!

      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @owner).first

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @forker)
      review.approve!

      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @owner).first

      assert_predicate  decision, :rules_fulfilled?
    end

    test "truncates codeowners list when very large" do
      users = (1..20).map do
        user = create(:user)
        @source.add_member user, action: :write
        user
      end
      user_string = users.map { |u| "@#{u.display_login}" }.join(" ")
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   #{user_string}
      CODEOWNERS

      assert_same_elements users, @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary

      assert decision.reason.message.start_with?("Waiting on code owner review from")
      assert_equal 10, decision.reason.message.count(",")
      assert decision.reason.message.include?(", and/or 10 others")
    end
  end

  test "Approval on differing base ref does not transfer" do
    @source.heads.create("other-master-forward-2", @source.heads.find("master-forward-2").target_oid, @source.owner)
    @source.heads.create("other-master", @source.heads.find("master").target_oid, @source.owner)
    pull = PullRequest.create_for!(@source,
      base: "other-master",
      head: "other-master-forward-2",
      user: @source.owner,
      title: "convert to CR line ending",
      body: "even more valuable PR",
    )

    review = pull.reviews.create(head_sha: pull.head_sha, user: @user)
    review.approve!

    ref_update = create_branch_update(@source, name: "master",
                                      before_oid: @source.heads["master"].target_oid,
                                      after_oid: @source.heads["other-master-forward-2"].target_oid)

    decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @owner).first

    refute_predicate  decision, :rules_fulfilled?
  end

  context "Soc 2 review compliance" do
    if GitHub.enterprise?
      test "is not enabled on GHE" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
        end
      end
    else
      test "only applies to hardcoded repositories" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync
        assert_predicate decision, :rules_fulfilled?

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync
          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_equal "Review from compliance team required", decision.reason.summary
        end
      end

      test "blocks with a helpful message if no compliance teams have been requested for review" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on review request to and subsequent approval from a compliance team"
        end
      end

      test "blocks with a helpful message if compliance team is requested but no one from the team has approved" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on approval from at least one compliance team"
        end
      end

      test "handles cases where a compliance team was requested and later dismissed" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        request = create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        request.dismiss
        request.save!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on review request to and subsequent approval from a compliance team"
        end
      end

      test "passes if a someone from a requested complicance team approves the PR" do
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_2

        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          assert_predicate decision, :rules_fulfilled?
        end
      end

      test "blocks is a member of a compliance team approves but the team was never requested" do
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?

          assert_includes decision.reason.message, "Waiting on review request to and subsequent approval from a compliance team"
        end
      end

      test "if a compliance team member approves before a request is created, they must re-approve to satisfy the process" do
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_2

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on approval from at least one compliance team"

          review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
          review.approve!
          @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync
          assert_predicate decision, :rules_fulfilled?
        end
      end

      test "falls back to normal review policy if a compliance team member requests changes" do
        request = create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member, body: "please fix")
        assert review.request_changes!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :changes_requested?
        end
      end

      test "correctly handles teams with human readable names" do
        compliance_team = create(:team, organization: @org, privacy: :closed, name: "Human-friendly compliance team")
        compliance_team.update! slug: "human-friendly-reviewers"
        compliance_team.add_member(@compliance_team_1_member)
        compliance_team.add_repository(@org_repo, :push)

        create :review_request, pull_request: @org_pull, reviewer: compliance_team
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_display_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).async_pull_request_review_policy_decision.sync

          assert_predicate decision, :rules_fulfilled?
        end
      end
    end
  end

  def commit_codeowners(pull, contents)
    # turn off protection so we can commit CODEOWNERS
    protected_branch = ProtectedBranch.for_repository_with_branch_name(pull.repository, pull.base_ref_name)
    protected_branch.clear_required_pull_request_reviews
    protected_branch.save

    pull.base_repository.refs.find(pull.base_ref_name).append_commit({ message: "Add CODEOWNERS file", committer: @owner }, @owner) do |files|
      files.add("CODEOWNERS", contents)
    end

    # Turn required reviews back on
    protected_branch.update! \
      pull_request_reviews_enforcement_level: :everyone,
      require_code_owner_review: true

    pull.reload
  end
end
