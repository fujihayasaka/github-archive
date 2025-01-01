# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewRuleTestBase < GitHub::TestCase
  include CommitTestHelper
  include GitHub::PullRequestReviewTestHelpers
  include RulesEngine::RefUpdateTestHelper
  include PullRequestSynchronizationTestHelpers
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
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
    Spokesd.enable_spokesd
  end

  # If empty, don't add content to commit
  def commit_and_push(ref, metadata: { message: "a commit", committer: @user }, author: @user, empty: false)
    freeze_time do
      with_enqueued_pr_sync_jobs do
        ref.append_commit(metadata, author) do |files|
          if block_given?
            yield files
          elsif !empty
            files.add("file.txt", <<~TEXT
                hello world!
                TEXT
            )
          end
        end
      end
    end
  end

  def web_commit_and_push(repo, user, branch, old_oid: GitHub::NULL_OID, files: { "new-file.txt" => "text" }, message: "a commit")
    freeze_time do
      with_enqueued_pr_sync_jobs do
        repo.commit_change_for_user(author: user, author_email: nil, branch: branch, files: files, message: message, before_oid: old_oid)
      end
    end
  end

  def org_repo_soc2_waiting_request_message
    "Waiting on review request to and subsequent approval from a compliance team"
  end

  # Used to test invariants which should not change when a FF is enabled
  def self.enable_and_disable_feature(feature, &block)
    context "#{feature} enabled" do
      block.call(-> { GitHub.flipper[feature].enable })
    end

    context "#{feature} disabled" do
      block.call(-> { GitHub.flipper[feature].disable })
    end
  end
end

class PullRequestReviewRuleTest < PullRequestReviewRuleTestBase
  context "cross repo pull request" do
    test "passes when there are approved reviews" do
      review1 = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @owner)
      review1.approve!
      refute_equal @reviewer, @pull.user

      merge_commit_oid = @cross_repo_pull.create_merge_commit

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)
      decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
      decision = decisions.first
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :code_owner_review_required?
      refute_predicate decision, :more_reviews_required?
    end
  end

  context "when the protected branch name contains a pattern rule" do
    test "denies when there are no PullRequestReviews" do
      @protected_branch.update!(name: "ma*")

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
    end
  end

  context "check for pull request" do
    test "denies when there are no PullRequestReviews" do
      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision

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
      review = @pull.reviews.create!(head_sha: @pull.head_sha, user: @read_only_user)
      review.approve!
      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message
      assert_predicate decision, :more_reviews_required?
      refute_predicate decision, :code_owner_review_required?
    end

    test "denies when there are only pending PullRequestReviews" do
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer)
      review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user)

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
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

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes for closed PR when there is at least one approval from a user other than the PR author" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
      review1.approve!
      refute_equal @reviewer, @pull.user

      @pull.close

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
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

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
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

      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
      assert_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
      refute_predicate decision, :changes_requested?
    end

    test "passes when there are no approvals and 0 are required" do
      @protected_branch.update!(required_approving_review_count: 0)

      merge_commit_oid = @pull.create_merge_commit
      ref_update = create_branch_update(@pull.repository, name: "master",
        before_oid: @pull.repository.heads["master"].target_oid,
        after_oid: merge_commit_oid)

      # We require an approval
      decision = RuleEngine::PullRequestReviewRule.check(@pull.repository, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
      refute_predicate decision, :changes_requested?
    end

    test "fails when PR is in draft mode and 0 reviewers are required" do
      @protected_branch.update!(required_approving_review_count: 0)
      @pull.convert_to_draft(user: @pull.user)

      merge_commit_oid = @pull.create_merge_commit
      ref_update = create_branch_update(@pull.repository,
        name: "master",
        before_oid: @pull.repository.heads["master"].target_oid,
        after_oid: merge_commit_oid)

      # We require an approval
      decision = RuleEngine::PullRequestReviewRule.check(@pull.repository, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      refute_predicate decision, :rules_fulfilled?
      refute_predicate decision, :approved?
      refute_predicate decision, :more_reviews_required?
      refute_predicate decision, :changes_requested?
    end

    test "fails when PR is in draft mode and 2 reviewers are required" do
      @protected_branch.update!(required_approving_review_count: 2)
      @pull.convert_to_draft(user: @pull.user)

      @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
      refute_equal @reviewer, @pull.user
      @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)
      refute_equal @another_reviewer, @pull.user

      merge_commit_oid = @pull.create_merge_commit
      ref_update = create_branch_update(@pull.repository,
        name: "master",
        before_oid: @pull.repository.heads["master"].target_oid,
        after_oid: merge_commit_oid)

      # We require an approval
      decision = RuleEngine::PullRequestReviewRule.check(@pull.repository, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      refute_predicate decision, :rules_fulfilled?
      refute_predicate decision, :approved?
      assert_predicate decision, :more_reviews_required?
      refute_predicate decision, :changes_requested?
    end

    context "when merge_queue is enabled" do
      test "denies when there are no reviews and the PR is NOT queued" do
        skip if GitHub.enterprise?

        GitHub.flipper[:merge_queue].enable(@source)

        @protected_branch.enable_merge_queue
        @protected_branch.merge_queue_enforcement_level = :everyone
        @protected_branch.save!

        mq_pull = create(:pull_request, :with_mergeable_head, repository: @source, user: @user)

        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
          @protected_branch.merge_queue.enqueue!(
            pull_request: mq_pull,
            enqueuer: @user,
          )
        end
        refute_predicate mq_pull, :in_merge_queue?

        decision = mq_pull.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        assert_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count but one of the approvers has pushed to the PR branch after it was opened when this is disallowed" do
      test "rejects when feature flag is on" do
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        another_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # @reviewer commits to the PR branch, disqualifying their earlier review
        with_enqueued_pr_sync_jobs do
          @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @reviewer }, @reviewer)
        end

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 2 approving reviews are required by reviewers with write access who have not pushed changes to this pull request after it was opened. 2 reviews from 'another-reviewer' and 'reviewer' were disqualified because of a subsequent push.", decision.reason.message
        assert_same_elements [disqualified_review.id, another_review.id], decision.instrumentation_payload[:disqualified_review_ids]
      end

      test "accepts when ignore_approvals_from_contributors config is disabled" do
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: false)

        @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # @reviewer commits to the PR branch
        with_enqueued_pr_sync_jobs do
          @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @reviewer }, @reviewer)
        end

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when disqualify approvals from contributors is enabled" do
      test "passes when checking the policy without a PR object and approved by someone who did not contribute" do
        # verify that policy checks do not require the actual PR to be present in the policy object
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)
        @protected_branch.update!(required_approving_review_count: 1, ignore_approvals_from_contributors: true)

        # freeze time to ensure push comes before reviews
        freeze_time do
          with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
            @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer)
          end
        end

        # Ensure reviews come after push by traveling in time
        travel 1.minute

        # reload fork and pr from db to fetch latest data from job
        @fork.reload
        @cross_repo_pull.reload

        merge_commit_oid = @cross_repo_pull.create_merge_commit

        ref_update = create_branch_update(@source,
          name: "master",
          before_oid: @source.heads["master"].target_oid,
          after_oid: merge_commit_oid)

        # A review from someone that didn't contribute counts
        review = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @fork.owner)
        review.approve!
        # Check the PR without the PR object
        decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?
      end

      test "rejects when approved by someone on a fork-specific branch who contributed after the PR was opened" do
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)
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
        decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message

        # @user approves
        review = @cross_repo_pull.reviews.create(head_sha: @cross_repo_pull.head_sha, user: @user).tap(&:approve!)
        decision = @cross_repo_pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count but one of the approvers has pushed to the PR branch before it was opened" do
      test "accepts when ignore_approvals_from_contributors config is enabled" do
        # This test asserts that pushes to a PR branch before it was opened do not disqualify a user as an approver
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        # @reviewer commits to the PR branch before the PR open
        before = @source.refs.find(@pull.head_ref).target.oid
        after = @source.refs.find(@pull.head_ref).append_commit({ message: "a commit", committer: @reviewer }, @reviewer)
        with_enqueued_pr_sync_jobs do
          trigger_push_event(
            @source.shard_path,
            @reviewer.login,
            [["refs/heads/#{@pull.head_ref}", before, after.sha]],
            1.day.ago,
          )
        end

        last_push = T.must(push_accessor.by_repository_id_and_refs(repository_id: @source.id, refs: ["refs/heads/#{@pull.head_ref}"], limit: 1).first)
        assert_equal(last_push.pusher_id, @reviewer.id)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "approval_count=required_count and ignore approvals from contributors and requiring approval for the last push are both enabled" do
      test "defers to the stricter ignore approvals policy" do
        GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)

        @protected_branch.update!(required_approving_review_count: 2, ignore_approvals_from_contributors: true)

        disqualified_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer).tap(&:approve!)
        another_review = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer).tap(&:approve!)

        decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # @reviewer commits to the PR branch, disqualifying their earlier review
        commit_and_push(@source.refs.find(@pull.head_ref), metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)

        decision = @pull.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
        assert_equal "At least 2 approving reviews are required by reviewers with write access who have not pushed changes to this pull request after it was opened. 1 review from 'reviewer' was disqualified because of a subsequent push.", decision.reason.message
        assert_equal [disqualified_review.id], decision.instrumentation_payload[:disqualified_review_ids]
      end
    end
  end

  context "#last_push_for_commit for push that creates a branch" do
    test "returns the most recent push" do
      GitHub.flipper[:last_reviewable_commit].enable(@protected_branch.repository)

      new_branch = "new-branch"
      # web commit and push to create a new branch with null before oid
      web_commit_and_push(@source, @source.owner, new_branch, old_oid: @source.refs.find("master").target.oid)
      pull = PullRequest.create_for!(@source,
        base: "master",
        head: new_branch,
        user: @user,
        title: "new branch pr",
        body: "a new pr",
      )

      last_push = push_accessor.latest_for_repo(repository_id: @source.id)
      assert_equal last_push&.ref, "refs/heads/#{new_branch}"
      # The initial push should have a non-existent push object as the before commit sha
      assert_equal GitHub::NULL_OID, T.must(last_push).before
      assert_raises(GitRPC::ObjectMissing) { @source.objects.read(T.must(last_push).before) }

      push = RuleEngine::PullRequestReviewRule.new(@source, [], [], actor: nil, pull_request: pull).send(
        :last_push_for_commit,
        last_push&.after,
        true,
        @source,
        []
      )

      assert_equal last_push, push
    end
  end

  context "#last_push_for_commit multiple non-reviewable pushed" do
  end

  context "#last_push_for_commit when exceeds timeout" do
  end

  context "#last_pusher_policy_info when the pusher has been deleted" do
    test "returns nil" do
      @protected_branch.update!(required_approving_review_count: 1, require_last_push_approval: true)
      ref = @source.refs.find(@pull.head_ref)
      before = ref.target.oid
      commit = ref.append_commit({ message: "test", author: @reviewer }, @reviewer) do |files|
        files.add("file.txt", <<~TEXT
          hello world!
          TEXT
        )
      end
      last_push = create :push,
        repository_id: @source.id,
        pusher_id: @another_reviewer.id,
        ref: "refs/heads/#{@pull.head_ref}",
        before: before,
        after: commit.oid,
        pushed_at: Time.now

      review = @pull.reviews.create!(head_sha: commit.oid, user: @reviewer)
      review.approve!
      # Ensure review is approved after the push
      review.update(submitted_at: DateTime.now + 1.day)

      # Delete the pusher
      @another_reviewer.destroy
      assert_nil User.find_by(id: @another_reviewer.id)
      # pusher_id should still be present
      # allows us to compare the review approvals to the pusher
      assert last_push.reload.pusher_id

      result = RuleEngine::PullRequestReviewRule.new(@source, [], [], actor: nil, pull_request: @pull).send(
        :last_pusher_policy_info,
        [review],
        build(:repository_rule_configuration, rule_type: "pull_request", parameters: { require_last_push_approval: true }),
        commit.oid,
        true
      )

      assert result.policy_met
      assert_nil result.last_push_user
    end
  end

  context "#pull_pusher_ids when repo is null" do
    test "returns empty" do
      ref = @source.refs.find(@pull.head_ref)
      commit_and_push(ref, metadata: { message: "a commit", committer: @reviewer }, author: @reviewer)
      last_push = push_accessor.latest_for_repo(repository_id: @source.id)

      review = create_pr_approval(@pull, @reviewer)

      @pull.head_repository = nil
      @pull.save(validate: false)

      result = RuleEngine::PullRequestReviewRule.new(@source, [], [], actor: nil, pull_request: @pull).send(
        :pull_pusher_ids,
        last_push&.after,
        true,
        [review]
      )

      assert_equal [], result
    end
  end

  context "last pusher rule only for user pushes" do
    # A system-generated commit happens when a user presses "Update Branch" on a PR
    # We only want to compare commits from user pushes
    context "when there's a system-generated merge" do
      test "the PR does not require additional approvals" do
        GitHub.flipper[:last_reviewable_commit].enable(@source)

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
        review = create_pr_approval(topic_pr, @reviewer, head_sha: commit.oid)
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when system-generated rebase" do
      test "the PR does not require additional approvals" do
        GitHub.flipper[:last_reviewable_commit].enable(@source)

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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "when a user pushes a commit without content" do
      test "the PR does not require additional approvals" do
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # User pushes no content
        commit_and_push(@source.reload.refs.find("topic"), empty: true)

        # Still approved
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?
      end
    end

    context "When there's a system-generated commit followed by a user push" do
      test "the PR requires additional approvals" do
        GitHub.flipper[:last_reviewable_commit].enable(@source)
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?
        assert_predicate decision, :approved?
        refute_predicate decision, :more_reviews_required?

        # Merge base into head
        topic_pr.reload.create_merge_commit

        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
            topic_pr.merge_base_into_head(
              user: @user,
              author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
              expected_head_oid: topic_pr.head_sha,
            )
          end
        end

        # User pushes another change
        commit_and_push(@source.reload.refs.find("topic")) do |files|
          files.add("new-new-file.txt", <<~TEXT
            NEW hello world!
            TEXT
          )
        end

        # Another approval is required
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
      end
    end

    context "When there's a user push followed by a system-generated commit" do
      test "the PR requires additional approvals" do
        GitHub.flipper[:last_reviewable_commit].enable(@source)
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
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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
        with_enqueued_pr_sync_jobs do
          topic_pr.merge_base_into_head(
            user: @user,
            author_email: @user.default_author_email(topic_pr.repository, topic_pr.head_sha),
            expected_head_oid: topic_pr.head_sha,
          )
        end

        # Another approval is required
        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
        refute_predicate decision, :rules_fulfilled?
        refute_predicate decision, :approved?
        assert_predicate decision, :more_reviews_required?
      end
    end

    context "when there is no PR" do
      test "the PR does not require additonal approvals if previously approved" do
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

        decision = topic_pr.reload.merge_state(viewer: @user).pull_request_review_policy_decision
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

        ref_update = create_branch_update(@source,
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

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision
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

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

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

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

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

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

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

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @forker)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "only requires one owner review per owned path" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @pr-creator @forker
      CODEOWNERS

      assert_same_elements [@user, @forker], @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from forker and/or pr-creator.", decision.reason.message

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "requires team member for team-owned path" do
      commit_codeowners(@org_pull, <<~CODEOWNERS)
        *   @#{@team.combined_slug}
      CODEOWNERS

      assert_same_elements [@team], @org_pull.codeowners.to_a

      decision = @org_pull.merge_state(viewer: @org_admin).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from #{@team.combined_slug}.", decision.reason.message

      review = @org_pull.reviews.create!(head_sha: @org_pull.head_sha, user: @team_member)
      review.approve!
      @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @org_pull.merge_state(viewer: @org_admin).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "allows sub-team member for team-owned path" do
      commit_codeowners(@org_pull, <<~CODEOWNERS)
        *   @#{@team.combined_slug}
      CODEOWNERS

      assert_same_elements [@team], @org_pull.codeowners.to_a

      decision = @org_pull.merge_state(viewer: @org_admin).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Code owner review required", decision.reason.summary
      assert_equal "Waiting on code owner review from #{@team.combined_slug}.", decision.reason.message

      review = @org_pull.reviews.create!(head_sha: @org_pull.head_sha, user: @sub_team_member)
      review.approve!
      @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @org_pull.merge_state(viewer: @org_admin).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "doesn't block if the PR author is the only code owner in the context of a PR" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @#{@cross_repo_pull.user}
      CODEOWNERS

      assert_same_elements [@cross_repo_pull.user], @cross_repo_pull.codeowners.to_a

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!
      @cross_repo_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      decision = @cross_repo_pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert_predicate decision, :rules_fulfilled?
    end

    test "doesn't block if the PR author is the only code owner outside the context of a PR" do
      commit_codeowners(@cross_repo_pull, <<~CODEOWNERS)
        file11   @#{@cross_repo_pull.user}
      CODEOWNERS

      assert_same_elements [@cross_repo_pull.user], @cross_repo_pull.codeowners.to_a

      merge_commit_oid = @cross_repo_pull.create_merge_commit
      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)

      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch.reload }, actor: @owner).first

      refute decision.rules_fulfilled?, "check passed when it should not have"
      assert_equal "Review required", decision.reason.summary

      review = @cross_repo_pull.reviews.create!(head_sha: @cross_repo_pull.head_sha, user: @user)
      review.approve!

      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @owner).first
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

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
        end
      end
    else
      test "only applies to hardcoded repositories" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision
        assert_predicate decision, :rules_fulfilled?

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision
          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_equal "Review from compliance team required", decision.reason.summary
        end
      end

      test "blocks with a helpful message if no compliance teams have been requested for review" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, org_repo_soc2_waiting_request_message
        end
      end

      test "blocks with a helpful message if compliance team is requested but no one from the team has approved" do
        review1 = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @team_member)
        review1.approve!
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

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

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on review request to and subsequent approval from a compliance team (i.e. '@github/*-reviewers')"
        end
      end

      test "passes if a someone from a requested complicance team approves the PR" do
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_2

        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          assert_predicate decision, :rules_fulfilled?
        end
      end

      test "blocks is a member of a compliance team approves but the team was never requested" do
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, org_repo_soc2_waiting_request_message
        end
      end

      test "if a compliance team member approves before a request is created, they must re-approve to satisfy the process" do
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        create :review_request, pull_request: @org_pull, reviewer: @compliance_team_2

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          refute_predicate decision, :rules_fulfilled?
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on approval from at least one compliance team"

          review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
          review.approve!
          @org_pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision
          assert_predicate decision, :rules_fulfilled?
        end
      end

      test "falls back to normal review policy if a compliance team member requests changes" do
        request = create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member, body: "please fix")
        assert review.request_changes!

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

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

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_pull.repository.name_with_owner]) do
          decision = @org_pull.merge_state(viewer: @team_member).pull_request_review_policy_decision

          assert_predicate decision, :rules_fulfilled?
        end
      end

      test "blocks when checking outside of the context of a PR" do
        review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
        review.approve!

        merge_commit_oid = @org_pull.create_merge_commit
        ref_update = create_branch_update(@org_repo, name: "master",
                                          before_oid: @org_repo.heads["master"].target_oid,
                                          after_oid: merge_commit_oid)

        RuleEngine::PullRequestReviewRule.stub_const(:SOC2_REPOS, [@org_repo.name_with_owner]) do
          decision = RuleEngine::PullRequestReviewRule.check(@org_repo, [ref_update], { "refs/heads/master" => @org_protected_branch.reload }, actor: @org_admin).first
          refute decision.rules_fulfilled?, "check passed when it should not have"
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on review request to and subsequent approval from a compliance team"

          request = create :review_request, pull_request: @org_pull, reviewer: @compliance_team_1

          decision = RuleEngine::PullRequestReviewRule.check(@org_repo, [ref_update], { "refs/heads/master" => @org_protected_branch.reload }, actor: @org_admin).first
          refute decision.rules_fulfilled?, "check passed when it should not have"
          assert_predicate decision, :soc2_approval_process_required?
          assert_includes decision.reason.message, "Waiting on approval from at least one compliance team: #{@compliance_team_1}"

          review = @org_pull.reviews.create(head_sha: @org_pull.head_sha, user: @compliance_team_1_member)
          review.approve!

          decision = RuleEngine::PullRequestReviewRule.check(@org_repo, [ref_update], { "refs/heads/master" => @org_protected_branch.reload }, actor: @org_admin).first
          assert_predicate  decision, :rules_fulfilled?
        end
      end
    end
  end

  test "denies when there are no PullRequestReviews" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first
    ref_update = create_branch_update(@source, name: "master",
                                      before_oid: @source.heads["master"].target_oid,
                                      after_oid: merge_commit.oid)
    decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
    decision = decisions.first

    refute_predicate decision, :rules_fulfilled?
    assert_predicate decision, :more_reviews_required?

    reason = decision.reason
    assert_equal "Review required", reason.summary
    assert_equal "At least 1 approving review is required by reviewers with write access.", reason.message
  end

  context "dismissed reviews" do
    test "denies when there is just one dimissed review" do
      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "bad")
      assert review1.request_changes!
      assert review1.dismiss!(@owner, message: "nah its okay")

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit.oid)
      decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
      decision = decisions.first

      refute_predicate decision, :rules_fulfilled?
    end

    test "message indicates there are no reviews when there is one dismissed review" do
      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "bad")
      assert review1.request_changes!
      assert review1.dismiss!(@owner, message: "nah its okay")

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit.oid)
      decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
      decision = decisions.first

      refute_predicate decision, :rules_fulfilled?
      reason = decision.reason
      assert_equal :review_policy_not_satisfied, reason.code
      assert_equal "Review required", reason.summary
      assert_equal "At least 1 approving review is required by reviewers with write access.", reason.message
    end

    test "one dismissed changes_requested and one approved review results in policy fulfilled" do
      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "bad")
      assert review1.request_changes!
      assert review1.dismiss!(@owner, message: "nah its okay")

      review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "bad")
      review2.approve!

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit.oid)
      decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
      decision = decisions.first
      assert_predicate decision, :rules_fulfilled?
    end

    test "reviews returns reviews without dismissed reviews" do
      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

      review1 = Timecop.freeze(2.minutes.ago) do
        @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "bad").tap do |review|
          assert review.request_changes!
          assert review.dismiss!(@owner, message: "nah its okay")
        end
      end

      review2 = Timecop.freeze(1.minute.ago) do
        @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @owner, body: "bad").tap { |r| assert r.approve! }
      end

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit.oid)
      decisions = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user)
      decision = decisions.first
      assert_equal [review2].map(&:id), decision.instrumentation_payload[:review_ids]
    end
  end

  test "compute_review_statuses always returns current for change requests" do
    approval = create_pr_approval(@pull, @reviewer)
    change_request = create_pr_change_request(@pull, @another_reviewer)
    comment = create_pr_comment_review(@pull, @forker)
    dismissal = create_pr_dismissed_review(@pull, @owner)

    review_statuses = @pull.compute_review_statuses

    # Only approvals and change requests are considered when processing review policies (see: latest_enforced_reviews)
    assert_equal :current, review_statuses[approval]
    assert_equal :current, review_statuses[change_request]
    assert_nil review_statuses[comment]
    assert_nil review_statuses[dismissal]

    # New changes pushed to head branch
    head_branch = @source.heads[@pull.head_ref]
    commit_and_push(@source.refs.find(@pull.head_ref)) { |f| f.add "file1", "1" }

    review_statuses = @pull.reload.compute_review_statuses

    # Only approvals become stale due to push; change requests remain current until dismissed
    assert_equal :stale_head_changed, review_statuses[approval]
    assert_equal :current, review_statuses[change_request]
    assert_nil review_statuses[comment]
    assert_nil review_statuses[dismissal]
  end

  test "denies when there are only pending PullRequestReviews" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer)
    review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user)

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length
    decision = decisions.first
    refute_predicate decision, :rules_fulfilled?

    reason = decision.reason
    assert_equal :review_policy_not_satisfied, reason.code
    assert_equal "Review required", reason.summary
    assert_equal "At least 1 approving review is required by reviewers with write access.", reason.message
  end

  test "denies when there are any requested changes PullRequestReviews" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = Timecop.freeze(2.minutes.ago) do
      @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "needs work").tap(&:request_changes!)
    end

    review2 = Timecop.freeze(1.minute.ago) do
      @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @owner, body: "approved").tap(&:approve!)
    end


    assert_equal 2, @pull.reviews.count

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length
    decision = decisions.first
    refute_predicate decision, :rules_fulfilled?
    assert_predicate decision, :changes_requested?

    reason = decision.reason
    assert_equal :review_policy_not_satisfied, reason.code
    assert_equal "Changes requested", reason.summary
    assert_equal "1 review requesting changes and 1 approving review by reviewers with write access.", reason.message
  end

  test "denies when there are only approvals from the non write users" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @read_only_user)
    review1.approve!

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length

    decision = decisions.first
    refute_predicate decision, :rules_fulfilled?, "policy should not be fulfilled: #{decision.reason.message}"
    assert_equal decision.reason.message, "At least 1 approving review is required by reviewers with write access."
  end

  test "passes when there are only approvals from the merge actor" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
    review1.approve!

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @reviewer)
    assert_equal 1, decisions.length
    assert_predicate decisions[0], :rules_fulfilled?
  end

  test "denies when there are only approvals from bots without write permission" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    integration = make_integration_installation(repository: @source, permissions: { "contents" => :read })

    @pull.reviews.create(head_sha: @pull.head_sha, user: integration.bot).tap(&:approve!)

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @reviewer)

    decision = decisions.first
    refute_predicate decision, :rules_fulfilled?, "policy should not be fulfilled: #{decision.reason.message}"
    assert_equal decision.reason.message, "At least 1 approving review is required by reviewers with write access."
  end

  test "passes when there is an approval from bots with write permission" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    integration = make_integration_installation(repository: @source, permissions: { "contents" => :write })

    @pull.reviews.create(head_sha: @pull.head_sha, user: integration.bot).tap(&:approve!)

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @reviewer)

    assert_equal 1, decisions.length
    assert_predicate decisions[0], :rules_fulfilled?
  end

  test "passes when there is a changes_requested review followed by a sign off by the same user" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    Timecop.freeze(1.week.ago) do
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "i request changes")
      review1.request_changes!
    end
    review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "sign off")
    review2.approve!

    review3 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user, body: "pending")

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length
    assert_predicate decisions[0], :rules_fulfilled?
  end

  test "passes when there is a changes_requested review by a non write user and a accept by a write user" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    Timecop.freeze(1.week.ago) do
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @read_only_user, body: "i request changes")
      review1.request_changes!
    end
    review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "sign off")
    review2.approve!

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length
    assert_predicate decisions[0], :rules_fulfilled?
  end

  test "passes when there is an accepted review followed by a comment review by the same user" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    Timecop.freeze(1.week.ago) do
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "This looks good")
      review1.approve!
    end

    review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @user, body: "Just clarifying...")
    review2.comment!

    review2 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "Yep, that's correct.")
    review2.comment!

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    assert_equal 1, decisions.length
    assert_predicate decisions[0], :rules_fulfilled?
  end

  test "passes when there is at least one approved PullRequestReview" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @reviewer)
    review1.approve!

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decision = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user).first
    assert_predicate decision, :rules_fulfilled?

    reason = decision.reason
    assert_equal "Changes approved", reason.summary
    assert_equal "1 approving review by reviewers with write access.", reason.message
  end

  test "returns the id's of reviews used in determining Decision in payload" do
    merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

    review1 = Timecop.freeze(2.minutes.ago) do
      @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer).tap(&:approve!)
    end

    review2 = Timecop.freeze(1.minute.ago) do
      @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @owner, body: "needs work").tap(&:request_changes!)
    end

    assert_equal 2, @pull.reviews.count

    ref_updates = [
      create_branch_update(@source,
        name: "master",
        before_oid: @source.heads["master"].target_oid,
        after_oid: merge_commit.oid),
    ]
    decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
    payload = decisions.first.instrumentation_payload
    assert_equal [review2.id, review1.id].sort, payload[:review_ids].sort
  end

  context "when there is no protected branch" do
    test "returns the id's of reviews used in determining Decision in payload" do
      @protected_branch.destroy

      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first
      review1 = @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer)
      review1.approve!

      ref_updates = [
        create_branch_update(@source,
        name: "master",
          before_oid: @source.heads["master"].target_oid,
          after_oid: merge_commit.oid),
      ]
      decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, { "refs/heads/master" => @protected_branch }, actor: @user)
      payload = decisions.first.instrumentation_payload
      assert_equal [review1.id], payload[:review_ids]
    end

    test "warns when there are any changes requested PullRequestReviews" do
      @protected_branch.destroy
      merge_commit = @source.commits.create_merge_commit(@user, "master", "master-forward-2").first

      review1 = Timecop.freeze(2.minutes.ago) do
        @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @reviewer, body: "needs work").tap(&:request_changes!)
      end

      review2 = Timecop.freeze(1.minute.ago) do
        @pull.reviews.create!(head_sha: @cr_line_endings_tip, user: @owner, body: "approved").tap(&:approve!)
      end

      assert_equal 2, @pull.reviews.count

      ref_updates = [
        create_branch_update(@source,
          name: "master",
          before_oid: @source.heads["master"].target_oid,
          after_oid: merge_commit.oid),
      ]
      decisions = RuleEngine::PullRequestReviewRule.check(@source, ref_updates, {}, actor: @user)
      assert_equal 1, decisions.length
      decision = decisions.first
      assert_predicate decision, :rules_fulfilled?

      reason = decision.reason
      assert_equal :review_policy_not_required, reason.code
    end
  end

  context "when there are multiple policies" do
    test "that each policy is evaluated and returns correctly" do
      review1 = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @owner)
      review1.approve!
      refute_equal @reviewer, @pull.user

      merge_commit_oid = @cross_repo_pull.create_merge_commit

      policies = [
        build(
          :repository_rule_configuration,
          rule_type: :pull_request,
          parameters: {
            required_approving_review_count: 1,
            require_code_owner_review: false,
            dismiss_stale_reviews_on_push: false,
            ignore_approvals_from_contributors: false,
            require_last_push_approval: false
          }
        ),
        build(
          :repository_rule_configuration,
          rule_type: :pull_request,
          parameters: {
            required_approving_review_count: 2,
            require_code_owner_review: false,
            dismiss_stale_reviews_on_push: false,
            ignore_approvals_from_contributors: false,
            require_last_push_approval: false
          }
        ),
      ]

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)
      decisions = RuleEngine::PullRequestReviewRule.check_policies(@source, [ref_update], { "refs/heads/master" => policies }, actor: @user)
      decision = decisions.first
      refute_predicate decision, :rules_fulfilled?
      assert_equal 2, decision.rule_decisions.size
      assert_predicate decision.rule_decisions[policies[0]], :rules_fulfilled?
      refute_predicate decision.rule_decisions[policies[1]], :rules_fulfilled?
    end

    test "two successful rules return success" do
      review1 = @pull.reviews.create(head_sha: @pull.head_sha, user: @owner)
      review2 = @pull.reviews.create(head_sha: @pull.head_sha, user: @another_reviewer)
      review1.approve!
      review2.approve!
      refute_equal @reviewer, @pull.user

      merge_commit_oid = @pull.create_merge_commit

      rules = [
        build(
          :repository_rule_configuration,
          rule_type: :pull_request,
          parameters: {
            required_approving_review_count: 1,
            require_code_owner_review: false,
            dismiss_stale_reviews_on_push: false,
            ignore_approvals_from_contributors: false,
            require_last_push_approval: false
          }
        ),
        build(
          :repository_rule_configuration,
          rule_type: :pull_request,
          parameters: {
            required_approving_review_count: 2,
            require_code_owner_review: false,
            dismiss_stale_reviews_on_push: false,
            ignore_approvals_from_contributors: false,
            require_last_push_approval: false
          }
        ),
      ]

      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)
      decisions = RuleEngine::PullRequestReviewRule.check_policies(@source, [ref_update], { "refs/heads/master" => rules }, actor: @user)
      decision = decisions.first
      assert_predicate decision, :rules_fulfilled?
      assert_equal 2, decision.rule_decisions.size
      assert_predicate decision.rule_decisions[rules[0]], :rules_fulfilled?
      assert_predicate decision.rule_decisions[rules[1]], :rules_fulfilled?
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

# These tests call share_spokesdb, which disables transactional tests. Calling this slows tests down drastically,
# so isolate the tests which need it to their own class.
class PullRequestReviewRuleTestSharedSpokes < PullRequestReviewRuleTestBase
  Spokesd.share_spokesdb(self)

  context "when disqualify approvals from contributors is enabled" do
    test "rejects when there are multiple PRs with the same head sha" do
      GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@protected_branch.repository)
      @protected_branch.update!(required_approving_review_count: 1, ignore_approvals_from_contributors: true)

      # another fork
      another_forker = create(:user, login: "another-forker")
      @fork.add_member another_forker, action: :write
      another_fork, msg = @fork.fork(forker: another_forker)
      example_repo :pull_request_fork, another_fork

      # freeze time to ensure push comes before reviews
      # push commit to original fork
      freeze_time do
        with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
          @fork.refs.find(@cross_repo_pull.head_ref).append_commit({ message: "a commit", committer: @another_reviewer }, @another_reviewer)
        end
      end

      # reload fork and pr from db to fetch latest data from job
      @fork.reload
      @cross_repo_pull.reload

      # Ensure reviews come after push by traveling in time
      travel 1.minute

      # sync with the original fork so commits are the same
      another_fork.refs.find("topic").fetch_and_merge(actor: another_fork.owner)

      # A duplicate PR from another repo
      another_cross_repo_pull = PullRequest.create_for!(@source,
        base: "owner:master",
        head: "another-forker:topic",
        user: @reviewer,
        title: "cross repo PR: merging another-forker:topic into master",
        body: "cross repo pull request",
      )

      merge_commit_oid = @cross_repo_pull.create_merge_commit
      ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: merge_commit_oid)

      # We require an approval
      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?
      assert_equal "At least 1 approving review is required by reviewers with write access.", decision.reason.message

      # A review for one PR
      review1 = @cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @user)
      review1.approve!
      decision = RuleEngine::PullRequestReviewRule.check(@source, [ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      # Valid because only one PR was found
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      another_merge_commit_oid = another_cross_repo_pull.create_merge_commit
      another_ref_update = create_branch_update(@source, name: "master",
                                        before_oid: @source.heads["master"].target_oid,
                                        after_oid: another_merge_commit_oid)
      # A review for the other PR
      review2 = another_cross_repo_pull.reviews.create(head_sha: @fork.heads["topic"].target_oid, user: @user)
      review2.approve!
      decision = RuleEngine::PullRequestReviewRule.check(@source, [another_ref_update], { "refs/heads/master" => @protected_branch }, actor: @user).first
      error_summary = "Multiple pull requests found"
      error_message = "Found multiple pull requests on the same commit from different repositories. Please close related PRs to proceed."
      refute_predicate decision, :rules_fulfilled?
      assert_equal error_summary, decision.reason.summary
      assert_equal error_message, decision.reason.message
    end
  end

  context "required discussion resolution" do
    test "passes when all comments are resolved within a merge commit" do
      review_repo = create :private_repository, name: "review_repo", from_example: :simple
      review_repo.add_member @owner, action: :write

      pull_thread = PullRequest.create_for!(review_repo,
        base: "master",
        head: "cr-line-endings",
        user: @owner,
        title: "convert to CR line ending",
        body: "most valuable PR ever A++++ please do merge",
      )

      policies = [
        build(
          :repository_rule_configuration,
          rule_type: :pull_request,
          parameters: {
            required_approving_review_count: 0,
            require_code_owner_review: false,
            dismiss_stale_reviews_on_push: false,
            ignore_approvals_from_contributors: false,
            require_last_push_approval: false,
            required_review_thread_resolution: true
          }
        ),
      ]

      comment = create(:pull_request_review_comment, pull_request: pull_thread, user: @owner)
      merge_commit_oid = pull_thread.create_merge_commit
      ref_update = create_branch_update(review_repo, name: "master",
        before_oid: review_repo.heads["master"].target_oid,
        after_oid: merge_commit_oid)

      # Create an unresolved comment
      comment = create(:pull_request_review_comment, pull_request: pull_thread, user: @owner)
      create(:pull_request_review, :commented, pull_request: pull_thread, user: @owner, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      # we should fail due to the unresolved comment
      decisions = RuleEngine::PullRequestReviewRule.check_policies(review_repo, [ref_update], { "refs/heads/master" => policies }, actor: @owner)
      decision = decisions.first
      refute_predicate decision, :rules_fulfilled?
      assert_equal "Conversation resolution required", decision.reason.summary
      assert_equal "A conversation must be resolved before this pull request can be merged.", decision.reason.message

      # resolve the comment
      comment.pull_request_review_thread.resolve(resolver: @owner)

      # We should pass since the comment is resolved
      decisions = RuleEngine::PullRequestReviewRule.check_policies(review_repo, [ref_update], { "refs/heads/master" => policies }, actor: @owner)
      decision = decisions.first
      assert_predicate decision, :rules_fulfilled?
    end
  end
end
