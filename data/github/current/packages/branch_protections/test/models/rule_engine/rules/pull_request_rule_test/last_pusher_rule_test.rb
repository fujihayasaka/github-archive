# typed: true
# frozen_string_literal: true

require "test_helper"

module RuleEngine::PullRequestRuleTest
  class LastPusherRuleTest < GitHub::TestCase
    include CommitTestHelper
    include GitHub::PullRequestReviewTestHelpers
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
      @forker = create(:user, login: "forker")

      @source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)

      @source.add_member @reviewer, action: :write
      @source.add_member @another_reviewer, action: :write
      @source.add_member @forker, action: :write
      @source.add_member @user, action: :write

      @fork, msg = @source.fork(forker: @forker)
      assert @fork, "forking #{@source} as #{@forker} failed: #{msg.inspect}"

      example_repo :pull_request_fork,   @fork

      # TODO: change to ruleset
      @protected_branch = create(:protected_branch, repository: @source, creator: @user,
        pull_request_reviews_enforcement_level: :everyone)

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
    end

    setup do
      example_repo_restore
      GitHub.flipper[:disqualify_pr_pushers_from_approving].disable(@protected_branch.repository)
    end

    test "it succeeds with 1 current approval from a different user" do
      @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
      commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

      # review after push
      travel 1.day

      @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

      decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
      assert_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
    end

    test "it succeeds with 1 current approval from the last pusher and a different user" do
      @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
      commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

      # review after push
      travel 1.day

      @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
      @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @user).tap(&:approve!)

      decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
      assert_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
    end


    context "when there are 0 current approvals and we don't look for the last pusher" do
      test "it fails with no approvals" do
        GitHub.flipper[:find_last_push_without_approvals].disable(@protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
      end

      test "it fails with 1 stale approval" do
        GitHub.flipper[:find_last_push_without_approvals].disable(@protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
      end

      test "it fails with 2 stale approvals" do
        GitHub.flipper[:find_last_push_without_approvals].disable(@protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
      end

      test "it fails with 3 stale approvals" do
        GitHub.flipper[:find_last_push_without_approvals].disable(@protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        @reviewer3 = create(:user, login: "reviewer3")
        @source.add_member(@reviewer3, action: :write)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer3).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        assert_equal "Waiting on 1 reapproval from someone other than the last pusher. 3 reviews are stale because they were submitted before the most recent code changes.", decision.reason.message
      end
    end

    context "when the last push is found" do
      test "it fails with no approvals" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "New changes require approval from someone other than #{@user.display_login} because they were the last pusher.", decision.reason.message
        else
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
        end
      end

      test "it fails with 1 current approval from the last pusher" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        travel 1.day
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @user).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "New changes require approval from someone other than #{@user.display_login} because they were the last pusher.", decision.reason.message
        else
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
        end
      end

      test "it fails with 1 stale approval from a different user" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "Waiting on 1 reapproval from someone other than #{@user.display_login} because they were the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end

      test "it fails with 2 stale approvals from different users" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "Waiting on 1 reapproval from someone other than #{@user.display_login} because they were the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
        end
      end

      test "it fails with 1 current approval from the last pusher and 1 stale approval from a different user" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

        # review after push
        travel 1.day

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @user).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "Waiting on 1 reapproval from someone other than #{@user.display_login} because they were the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end

      test "it fails with 1 current approval from the last pusher and 2 stale approvals from a different users" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # push after review
        travel 1.day
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

        # review after push
        travel 1.day
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @user).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "Waiting on 1 reapproval from someone other than #{@user.display_login} because they were the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
        end
      end

      test "it fails with 1 stale approval from the last pusher" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @user).tap(&:approve!)

        # push after review
        travel 1.day

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "New changes require approval from someone other than #{@user.display_login} because they were the last pusher.", decision.reason.message
        else
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
        end
      end
    end

    context "when the last push is not found" do
      test "it succeeds with 2 current approvals" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

        # review after push
        travel 1.day

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        # Force scenario where push isnt found
        RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end

      context "when required approvals is less than 2" do
        test "it fails with no approvals" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "Waiting on 2 approvals from reviewers with write access because the last pusher could not be determined.", decision.reason.message
          else
            assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
          end
        end

        test "it fails with 1 stale review" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          travel 1.day

          # push after review
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "Waiting on 2 reapprovals from reviewers with write access because the last pusher could not be determined. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          end
        end

        test "it fails with 2 stale reviews" do

          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

          travel 1.day

          # push after review
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "Waiting on 2 reapprovals from reviewers with write access because the last pusher could not be determined. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
          end
        end

        test "it fails with 1 current review" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          assert_equal "Waiting on 1 more approval from a reviewer with write access because the last pusher could not be determined.", decision.reason.message
        end

        test "it fails with 1 current and 1 stale reviews" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          travel 1.day

          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # review after push
          travel 1.day

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          assert_equal "Waiting on 1 more approval from a reviewer with write access because the last pusher could not be determined. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end

      context "when required approvals is 2 or more" do
        test "it fails with no approvals" do
          @protected_branch.update!(required_approving_review_count: 2, require_last_push_approval: true)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "At least 2 approving reviews are required by reviewers with write access.", decision.reason.message
          else
            assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
          end
        end

        test "it fails with 1 stale review" do
          @protected_branch.update!(required_approving_review_count: 2, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          travel 1.day

          # push after review
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "At least 2 approving reviews are required by reviewers with write access. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          end
        end

        test "it fails with 2 stale reviews" do

          @protected_branch.update!(required_approving_review_count: 2, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

          travel 1.day

          # push after review
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "At least 2 approving reviews are required by reviewers with write access. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Reviews from #{@another_reviewer.display_login} and #{@reviewer.display_login} are stale because they were submitted before the most recent code changes.", decision.reason.message
          end
        end

        test "it fails with 1 current review" do
          @protected_branch.update!(required_approving_review_count: 2, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule::LastPushPolicyResult.any_instance.stubs(:push_not_found).returns(true)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          assert_equal "At least 2 approving reviews are required by reviewers with write access.", decision.reason.message
        end

        test "it fails with 1 current and 1 stale reviews" do
          @protected_branch.update!(required_approving_review_count: 2, require_last_push_approval: true)

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

          travel 1.day

          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)

          # review after push
          travel 1.day

          @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

          # Force scenario where push isnt found
          RuleEngine::PullRequestStrictReviewRule.any_instance.stubs(:last_reviewable_push).returns(nil)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          assert_equal "At least 2 approving reviews are required by reviewers with write access. Review from #{@reviewer.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end
    end

    context "when last pusher rule is enabled and pr involves bot" do
      test "a push by a bot can be approved" do

        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        integration = make_integration_installation(repository: @source, permissions: { "contents" => :write })

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: integration.bot }, author: integration.bot)
        # ensure review comes after push
        travel 1.minute
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end

      test "a push by a user cannot be approved by a bot with readonly access" do

        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        integration = make_integration_installation(repository: @source, permissions: { "contents" => :read })

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        # ensure review comes after push
        travel 1.minute
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: integration.bot).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "New changes require approval from someone other than #{@user.display_login} because they were the last pusher.", decision.reason.message
        else
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
        end
      end

      test "a push by a user can be approved by a bot with write access" do

        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        integration = make_integration_installation(repository: @source, permissions: { "contents" => :write })

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: @user)
        # ensure review comes after push
        travel 1.minute
        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: integration.bot).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end

      test "A bot cannot approve own push" do

        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
        integration = make_integration_installation(repository: @source, permissions: { "contents" => :write })

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @user }, author: integration.bot)

        # ensure review comes after push
        travel 1.minute
        @pull.reviews.create(head_sha: @pull.head_sha, user: integration.bot).tap(&:approve!)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        if GitHub.flipper[:find_last_push_without_approvals].enabled?
          assert_equal "New changes require approval from someone other than #{integration.bot.display_login} because they were the last pusher.", decision.reason.message
        else
          assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{integration.bot.display_login} is stale because it was submitted before the most recent code changes.", decision.reason.message
        end
      end
    end

    context "approval_count=required_count but the last pusher to push after the PR was opened approves the PR" do
      context "when require last push approval is enabled" do
        test "accepts the approval but requires more reviews when approval is required for the last push" do

          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          # Unapproved change by reviewer does not satisfy the policy
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer, pushed_at: 1.day.ago)
          @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          @pull.reload

          last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
          assert_equal(last_push.pusher_id, @reviewer.id)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            message = "New changes require approval from someone other than #{@reviewer.login} because they were the last pusher."
          else
            message = "New changes require approval from someone other than the last pusher."
          end
          assert_equal message, decision.reason.message
          # reviewer approves, but this does not satisfy the policy since they pushed to the branch last
          review1 = @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
          decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
          assert_equal :approved, PullRequestReview.state_name(review1.state)
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          assert_equal "New changes require approval from someone other than #{@reviewer.login} because they were the last pusher.", decision.reason.message

          # another_reviewer approves satisfying the policy
          review2 = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
          @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?

          # another_review pushes a change disqualifying their approval
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @another_reviewer }, author: @another_reviewer) do |files|
            files.add("another-file.txt", <<~TEXT
              hello world!
              TEXT
            )
          end

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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
          @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          assert_equal(1, PullRequestReview.where(repository_id: @source.id, id: review3.id).update_all(submitted_at: 1.day.from_now))
          decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end

        test "handles missing last pusher" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          head_1 = @pull.head_sha
          approval_1 = @pull.reviews.create(head_sha: head_1, user: @reviewer).tap(&:approve!)

          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision

          # There's no push record here
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "Waiting on 1 more approval from a reviewer with write access because the last pusher could not be determined.", decision.reason.message

          # Add a change
          pusher = create :user
          commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: pusher, pushed_at: 1.day.ago, empty: false)
          @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews
          @pull.reload

          # @reviewer approves the new head
          head_2 = @pull.head_sha
          approval_2 = @pull.reviews.create(head_sha: head_2, user: @reviewer).tap(&:approve!)

          # @reviewer != pusher, so we have two sets of eyes
          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision

          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?

          # User who pushed last is deleted / removed from the repo / etc.
          pusher.destroy!

          last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
          assert_nil(last_push.pusher)

          # @reviewer != pusher, so we have two sets of eyes
          decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision

          # Approval is still not from the pusher, even though pusher went away
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end

        context "when require last push approval is disabled" do
          test "accepts the approval and the review" do
            @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: false)
            @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)

            # @reviewer commits to the PR branch
            commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

            decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
            assert_predicate decision, :rules_fulfilled?
            assert_predicate decision, :approved?
            refute_predicate decision, :more_reviews_required?
          end
        end
      end
    end

    context "approval_count=required_count but the last pusher to push before the PR was opened approves the PR" do
      test "accepts the approval but requires additional reviews to merge" do
        # This test asserts that if the last pusher to a branch before PR also approves the PR,
        # that it still requires additional reviews to satisfy the PR

        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        # @reviewer commits to the PR branch
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer, pushed_at: 1.day.ago)

        # manipulate things so the push is before the PR open
        last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
        assert_equal(last_push.pusher_id, @reviewer.id)

        @pull.reload
        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
        assert disqualified_review.approved?
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?

        # Someone other than the last pusher can approve the PR
        another_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
        @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

        decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
        assert another_review.approved?
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count but the last pusher to the fork approves the PR" do
      context "when the push came before the PR" do
        test "accept the approval but requires additional reviews" do
          @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

          @fork.add_member @user, action: :write
          @fork.add_member @another_reviewer, action: :write

          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?

          # @another_reviewer commits to the PR branch
          # push is before pr is opened
          travel(-1.day) do
            with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
              @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer) do |files|
                files.add("new.txt", "text")
              end
            end
          end

          # @another_reviewer's approval is accepted, but still require additional approval
          @cross_repo_pull.reload.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than #{@another_reviewer.login} because they were the last pusher.", decision.reason.message

          @cross_repo_pull.reload.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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
          commit_and_push(@fork.refs.find(@cross_repo_pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

          # Ensure that the review comes after the push
          travel 1.minute
          # Review is accepted
          review = @cross_repo_pull.reload.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?

          # Ensure that the push comes after the review
          travel 1.minute

          # @another_reviewer commits to the PR branch, previous review is ignored
          # freeze time to ensure push comes before reviews
          commit_and_push(@fork.refs.find(@cross_repo_pull.head_ref), metadata: { message: "a commit", committer: @another_reviewer }, author: @another_reviewer) do |files|
            files.add("another-file.txt", <<~TEXT
              hello world!
              TEXT
            )
          end

          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          if GitHub.flipper[:find_last_push_without_approvals].enabled?
            assert_equal "New changes require approval from someone other than #{@another_reviewer.login} because they were the last pusher.", decision.reason.message
          else
            assert_equal "Waiting on 1 reapproval from someone other than the last pusher. Review from #{@another_reviewer.login} is stale because it was submitted before the most recent code changes.", decision.reason.message
          end

          # Ensure that the review comes after the push
          travel 1.minute
          # @another_reviewer's attempts to approve again, but we still require additional approval
          review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          refute_predicate decision, :approved?
          assert_predicate decision, :more_reviews_required?
          assert_equal "New changes require approval from someone other than #{@another_reviewer.login} because they were the last pusher.", decision.reason.message

          # Ensure that the review comes after the push
          travel 1.minute
          review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
          decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
          assert_predicate decision, :approved?
          refute_predicate decision, :more_reviews_required?
        end
      end

      test "Handles missing last pusher" do
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @fork.add_member @user, action: :write
        @fork.add_member @another_reviewer, action: :write

        # freeze time to ensure push comes before reviews
        pusher = create :user
        commit_and_push(@fork.refs.find(@cross_repo_pull.head_ref), metadata: { message: "a commit", committer: @another_reviewer }, author: pusher, pushed_at: 1.day.ago)
        pusher.destroy!

        last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @fork.id, refs: ["refs/heads/#{@cross_repo_pull.head_ref}"], limit: 1).first)
        assert_nil(last_push.pusher)

        decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message

        # Ensure that the review comes after the push
        travel 1.minute
        # @another_reviewer's approves
        review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @another_reviewer).tap(&:approve!)
        decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count and last pusher policy is enabled" do
      test "passes when checking the policy without a PR object and approved by someone other than the last pusher" do
        # verify that policy checks do not require the actualy PR to be present in the policy object
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        @fork.add_member @user, action: :write
        @fork.add_member @another_reviewer, action: :write

        # freeze time to ensure push comes before reviews
        freeze_time do
          with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
            @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer) do |files|
              files.add("text.txt", "text")
            end
          end
        end

        # Ensure reviews come after push by traveling in time
        travel 1.minute

        # reload fork and pr from db to fetch latest data from job
        @fork.reload
        @cross_repo_pull.reload

        # A review from the last pusher will not be counted
        review1 = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @another_reviewer)
        review1.approve!

        merge_commit_oid = @cross_repo_pull.create_merge_commit

        ref_update = create_branch_update(@source, name: "master",
                                          before_oid: @source.heads["master"].target_oid,
                                          after_oid: merge_commit_oid)

        decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
        decision = decisions.first

        refute_predicate decision, :rules_fulfilled?
        assert_predicate decision, :more_reviews_required?
        assert_equal "New changes require approval from someone other than #{@another_reviewer.login} because they were the last pusher.", decision.reason.message

        # A review from someone other than the last pusher will be counted
        review2 = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @fork.owner)
        review2.approve!

        decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
        decision = decisions.first

        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?
      end

      test "rejects when there is no head repository" do
        # Repositories can be deleted, which won't delete the associated PRs/reviews
        @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        @pull.head_repository = nil
        @pull.save!(validate: false)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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

    context "approval_count=0 and the last pusher policy is enabled" do
      test "rejects without approvals" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        # Unapproved change by reviewer does not satisfy the policy
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        travel 1.minute

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        message = if GitHub.flipper[:find_last_push_without_approvals].enabled?
          "New changes require approval from someone other than #{@reviewer.login} because they were the last pusher."
        else
          "New changes require approval from someone other than the last pusher."
        end
        assert_equal message, decision.reason.message
      end

      test "rejects when the last pusher is the only approver" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        travel 1.minute

        review1 = @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "New changes require approval from someone other than #{@reviewer.login} because they were the last pusher.", decision.reason.message

        review2 = @pull.reviews.create(head_sha: @pull.head_sha, user: @source.owner).tap(&:approve!)
        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end

      test "accepts when someone other than the last pusher approves" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        travel 1.minute

        review1 = @pull.reload.reviews.create(head_sha: @pull.head_sha, user: @source.owner).tap(&:approve!)
        decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end

      test "accepts without a PR object" do
        @protected_branch.update!(required_approving_review_count: 0, require_last_push_approval: true)

        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        travel 1.minute

        merge_commit_oid = @pull.reload.create_merge_commit

        ref_update = create_branch_update(@source, name: "master",
                                          before_oid: @source.heads["master"].target_oid,
                                          after_oid: merge_commit_oid)

        # We require an approval
        decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
        decision = decisions.first
        refute_predicate decision, :rules_fulfilled?
        assert_predicate decision, :more_reviews_required?
        message = if GitHub.flipper[:find_last_push_without_approvals].enabled?
          "New changes require approval from someone other than #{@reviewer.login} because they were the last pusher."
        else
          "New changes require approval from someone other than the last pusher."
        end
        assert_equal message, decision.reason.message

        review = @pull.reviews.create(head_sha: @source.heads["master-forward-2"].target_oid, user: @source.owner)
        review.approve!
        decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
        decision = decisions.first
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?
      end
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
  end
end
