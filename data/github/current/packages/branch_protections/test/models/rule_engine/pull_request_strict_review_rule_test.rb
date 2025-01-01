# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestStrictReviewRuleTest < GitHub::TestCase
  include CommitTestHelper
  include GitHub::PullRequestReviewTestHelpers
  include RulesEngine::RefUpdateTestHelper
  include PullRequestSynchronizationTestHelpers

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @user = create(:user, login: "pr-creator")
    @reviewer = create(:user, login: "reviewer")
    @another_reviewer = create(:user, login: "another-reviewer")
    @read_only_user = create(:user, login: "read-only-user")
    @forker = create(:user, login: "forker")

    @org = create(:organization, plan: "business_plus")
    @org_admin = @org.admins.first
    @org_repo = create(:private_repository, owner: @org, from_example: :pull_request_source)
    @org_reviewer = create(:user, login: "org-reviewer")
    @org.add_member(@org_reviewer)
    @org_repo.add_member(@org_reviewer, action: :write)

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
      user: @forker,
      title: "cross repo PR: merging forker:topic into master",
      body: "cross repo pull request",
    )

    @org_pull = PullRequest.create_for!(@org_repo,
      base: "master",
      head: "master-forward-2",
      user: @org_admin,
      title: "convert to CR line ending",
      body: "most valuable PR ever A++++ please do merge",
    )
  end

  setup do
    example_repo_restore

    Spokesd.enable_spokesd
  end

  def get_check_decision(pull:, after_oid:, protection:)
    get_check_decision_for_rule(pull:, after_oid:, rule_configs: [protection.pull_request_policy], user: @user)
  end

  def get_check_decision_for_rule(pull:, after_oid:, rule_configs:, user:)
    pull.reload
    qualified_ref_name = "refs/heads/#{pull.base_ref}"

    ref_update = create_ref_update(
      pull.repository,
      name: qualified_ref_name,
      before_oid: pull.base_repository.heads[pull.base_ref].target_oid,
      after_oid: after_oid)

    RuleEngine::PullRequestStrictReviewRule.check_policies(pull.repository, [ref_update], { qualified_ref_name => rule_configs }, actor: user)
      .first
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

  context "cross repo pull request" do
    test "passes only when there are approved reviews" do
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true)
      pull = @cross_repo_pull

      merge_commit_oid = pull.create_merge_commit
      merge_commit = @source.commits.find(merge_commit_oid)

      # Trying to merge with no reviews fails
      decision = get_check_decision(pull: pull, after_oid: merge_commit_oid, protection: @protected_branch)
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?
      assert_equal decision.reason.code, :review_policy_not_satisfied

      # Add an approval
      review1 = create_pr_approval(pull, @reviewer)

      # Trying to merge with 1 approval succeeds
      decision = get_check_decision(pull: pull, after_oid: merge_commit_oid, protection: @protected_branch)
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?
    end

    test "when pushed merge is tree-equal to system merge" do
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true)
      pull = @cross_repo_pull

      system_merge_commit_oid = pull.create_merge_commit
      system_merge_commit = @source.commits.find(system_merge_commit_oid)

      # Add an approval
      review1 = create_pr_approval(pull, @reviewer)

      # Pushing system-created merge succeeds
      decision = get_check_decision(pull: pull, after_oid: system_merge_commit_oid, protection: @protected_branch)
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # User creates their own merge commit, with different metadata but same file contents
      user_created_merge_commit_oid = @source.create_merge_commit(
        system_merge_commit.parent_oids.first, system_merge_commit.parent_oids.second,
        { name: "Custom Author Name", email: "Internal email", time: Time.now },
        "My own commit message which I like much better",
        { tree: system_merge_commit.tree_oid }
      ).first
      user_created_merge_commit = @source.commits.find(user_created_merge_commit_oid)

      # User merge commit should have same parents as system-created merge, and same contents
      assert_equal system_merge_commit.parent_oids, user_created_merge_commit.parent_oids
      assert_equal system_merge_commit.tree_oid, user_created_merge_commit.tree_oid

      # Pushing custom merge with same contents as system-created merge succeeds
      decision = get_check_decision(pull: pull, after_oid: user_created_merge_commit_oid, protection: @protected_branch)
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?
    end

    test "when pushed merge is not tree-equal to system merge" do
      pull = @cross_repo_pull

      system_merge_commit_oid = pull.create_merge_commit
      system_merge_commit = @source.commits.find(system_merge_commit_oid)

      # Add an approval
      review1 = create_pr_approval(pull, @reviewer)

      # User creates their own merge commit, with different metadata and altered file contents
      altered_commit = @source.create_commit(system_merge_commit_oid,
        message: "Merge with unreviewed changes",
        author: { name: "Custom Author Name", email: "Internal email", time: Time.now },
        files: { "unreviewed_file" => "file contents" },
        sign: false)

      altered_merge_commit_oid = @source.create_merge_commit(
        system_merge_commit.parent_oids.first, system_merge_commit.parent_oids.second,
        { name: "Custom Author Name", email: "Internal email", time: Time.now },
        "My own commit message which I like much better",
        { tree: altered_commit.tree_oid }
      ).first
      altered_merge_commit = @source.commits.find(altered_merge_commit_oid)

      # Altered merge commit should have same parents as system-created merge, but different contents
      assert_equal system_merge_commit.parent_oids, altered_merge_commit.parent_oids
      refute_equal system_merge_commit.tree_oid, altered_merge_commit.tree_oid

      # Non-strict branch protection rule
      @protected_branch.update!(required_approving_review_count: 1,
        require_last_push_approval: false, dismiss_stale_reviews_on_push: false)

      # Pushing custom merge with altered contents from system-created merge succeeds when strict policy not enabled
      decision = get_check_decision(pull: pull, after_oid: altered_merge_commit_oid, protection: @protected_branch)
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # Strict branch protection rule (last push approval)
      @protected_branch.update!(required_approving_review_count: 1,
        require_last_push_approval: true, dismiss_stale_reviews_on_push: false)

      # Pushing custom merge with altered contents from system-created merge fails when strict policy is enabled
      decision = get_check_decision(pull: pull, after_oid: altered_merge_commit_oid, protection: @protected_branch)
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      # Strict branch protection rule (review dismissal)
      @protected_branch.update!(required_approving_review_count: 1,
        require_last_push_approval: false, dismiss_stale_reviews_on_push: true)

      # Pushing custom merge with altered contents from system-created merge fails when strict policy is enabled
      decision = get_check_decision(pull: pull, after_oid: altered_merge_commit_oid, protection: @protected_branch)
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?
    end

    test "when merge-base changes after review is submitted" do
      # In this attack, a vulnerability is introduced in commits A and D, but removed in commits B and C.
      # When PR2 is reviewed, the file with the vulnerability will not appear in the diff, because the merge base is A.
      # Relative to A, the vulnerability is first removed (at C) and then added (at D). There is no difference in the
      # vulnerable file between A (the merge base) and D (the head). As a result, the change is invisible on the diff page.
      #
      # For the same reason, PR1 shows no vulnerability because both B and C do not contain the vulnerability.
      #
      # After PR2 is reviewed and approved, the attacker merges PR1. Once PR1 is merged, the merge-base for PR2 changes
      # from A to D. Now PR2 contains only commit D, so merging PR2 quickly will add the vulnerability to the mainline.
      #
      # The way we prevent this is by watching for the merge-base to change between after a review was submitted, and
      # treating that as "new content added to the pull request". That means that if reviews are being dismissed by policy,
      # PR2 would need to regather reviews after PR1 merges.
      #
      #        base        master
      #      ↙           ↙
      # o———o—————o—————o · · · ◌ · · ◌
      #      ╲         ╱       ·     ·
      #      (A)—————(B)      ·     ·
      #        ╲       ╲     ·     ·
      #         ╲       *———o ←—— topic1 / PR1
      #          ╲     ╱         ·
      #           *——(C)        ·
      #                ╲       ·
      #                 *———(D) ←— topic2 / PR2
      #

      metadata = { message: "msg", committer: @user }

      # Turn off branch protection while we build our initial state
      @protected_branch.update!(pull_request_reviews_enforcement_level: :off)

      # Run all the standard push-related jobs. For one thing, without jobs the pushes table will be empty
      with_enqueued_pr_sync_jobs(additional_jobs: [PullRequests::UpdateReviewsJob]) do
        master_branch = @source.heads["master"]
        initial_master_oid = master_branch.target_oid

        base = @source.commits.find(master_branch.target.parent_oids.first)

        topic2_branch = @source.heads.create("topic2", base.oid, @user)
        travel 2.seconds
        commit_a = topic2_branch.append_commit(metadata, @user) { |f| f.add "file1", "1" }
        travel 2.seconds
        commit_c = topic2_branch.append_commit(metadata, @user) { |f| f.add "file2", "2" }
        travel 2.seconds
        commit_d = topic2_branch.append_commit(metadata, @user) { |f| f.add "file3", "3" }
        travel 2.seconds

        topic1_branch = @source.heads.create("topic1", commit_a.oid, @user)
        travel 2.seconds
        commit_b = topic1_branch.append_commit(metadata, @user) { |f| f.add "file4", "4" }
        travel 2.seconds

        # Merge commit B onto master
        master_merge_commit = @source.commits.create_merge_commit(@user, "master", commit_b.oid).first
        master_branch.update(master_merge_commit.oid, @user)
        travel 2.seconds

        # Merge commit C onto topic1
        topic1_merge_commit = @source.commits.create_merge_commit(@user, "topic1", commit_c.oid).first
        topic1_branch.update(topic1_merge_commit.oid, @user)
        travel 2.seconds

        # Check that our repo looks like the diagram above
        assert_equal master_branch.target_oid, master_merge_commit.oid
        assert_equal master_merge_commit.parent_oids, [initial_master_oid, commit_b.oid]

        assert_equal topic1_branch.target_oid, topic1_merge_commit.oid
        assert_equal topic1_merge_commit.parent_oids, [commit_b.oid, commit_c.oid]

        assert_equal topic2_branch.target_oid, commit_d.oid

        assert_equal commit_d.parent_oids, [commit_c.oid]
        assert_equal commit_c.parent_oids, [commit_a.oid]
        assert_equal commit_b.parent_oids, [commit_a.oid]
        assert_equal commit_a.parent_oids, [base.oid]

        # Create PR2
        pr2 = PullRequest.create_for!(@source,
          base: "master", head: "topic2",
          user: @user,
          title: "Not a malicious PR, nothing to see here", body: "Totally harmless I promise")
        pr2_merge_base_oid = pr2.find_best_merge_base_sha(use_current_base_sha: true)

        # PR2 is at commit D, and the best merge base is currently commit A
        assert_equal pr2.head_sha, commit_d.oid
        assert_equal pr2_merge_base_oid, commit_a.oid

        # Reviewer approves PR2
        review = create_pr_approval(pr2, @reviewer)

        pr2_system_merge_commit_oid = pr2.create_merge_commit

        # Turn branch protection on
        @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 1)

        # With non-strict protection, merge should fulfill policy (merge-base hasn't changed)
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # With strict protection, merge should fulfill policy (merge-base hasn't changed)
        @protected_branch.update!(require_last_push_approval: true, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # With strict protection, merge should fulfill policy (merge-base hasn't changed)
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: true)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # Now merge PR1/topic1, which will cause the merge-base of PR2 to change
        master_merge_commit = @source.commits.create_merge_commit(@user, "master", "topic1").first
        @protected_branch.update!(pull_request_reviews_enforcement_level: :off)
        master_branch.update(master_merge_commit.oid, @user)
        travel 2.seconds
        @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

        # Create a new merge for PR2
        pr2.reload
        pr2_system_merge_commit_oid = pr2.create_merge_commit
        pr2_system_merge_commit = @source.commits.find(pr2_system_merge_commit_oid)

        pr2.reload
        pr2_merge_base_oid = pr2.find_best_merge_base_sha(use_current_base_sha: true)

        # PR2 is at commit D, and the best merge base has moved to commit C
        assert_equal pr2.head_sha, commit_d.oid
        assert_equal pr2_merge_base_oid, commit_c.oid

        # With non-strict protection, merge should fulfill policy even though merge-base has changed
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # With strict protection, merge should fail policy because merge-base has changed
        @protected_branch.update!(require_last_push_approval: true, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        refute_predicate decision, :rules_fulfilled?
        assert_predicate decision, :more_reviews_required?
        if GitHub.flipper[:new_last_pusher_messaging].enabled?
          assert_equal "Waiting on 1 reapproval from someone other than #{@user.display_login} because they were the last pusher. Review from #{@reviewer.display_login} is stale because it was submitted before the merge base changed.", decision.reason.message
        else
          assert_equal "New changes require approval from someone other than the last pusher.", decision.reason.message
        end

        # With strict protection, merge should fail policy because merge-base has changed
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: true)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        refute_predicate decision, :rules_fulfilled?
        assert_predicate decision, :more_reviews_required?

        assert review.reload.dismissed?
        pr2.reload
        review = create_pr_approval(pr2, @reviewer)

        # With non-strict protection, merge should fulfill policy (merge-base hasn't changed since re-approval)
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # With strict protection, merge should fulfill policy (merge-base hasn't changed since re-approval)
        @protected_branch.update!(require_last_push_approval: true, dismiss_stale_reviews_on_push: false)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?

        # With strict protection, merge should fulfill policy (merge-base hasn't changed since re-approval)
        @protected_branch.update!(require_last_push_approval: false, dismiss_stale_reviews_on_push: true)
        decision = get_check_decision(pull: pr2, after_oid: pr2_system_merge_commit_oid, protection: @protected_branch)
        assert_predicate decision, :rules_fulfilled?
        refute_predicate decision, :more_reviews_required?
      end
    end
  end

  # Set up a test where there are 3 PR's in-flight:
  #   pr_a from commit (A)
  #   pr_b1 and pr_b2 both from commit (B).
  #
  #        master
  #      ↙
  # o———o · · · · ◌
  #      ╲       ·
  #      (A)———(B)
  #
  # Merging either pr_b1 or pr_b2 will cause the contents of all 3 PR's to be added to master.
  def setup_3_pr_test
    @protected_branch.destroy!
    ruleset1 = create(:repository_ruleset, :targets_default_branch, source: @source)
    create(:repository_rule_configuration, repository_ruleset: ruleset1, rule_type: "pull_request", parameters: {
      required_approving_review_count: 1,
      require_code_owner_review: false,
      dismiss_stale_reviews_on_push: false,
      ignore_approvals_from_contributors: false,
      require_last_push_approval: false,
      authorized_dismissal_actors_only: false,
      required_review_thread_resolution: false
    })

    metadata = { message: "msg", committer: @user }

    master_branch = @source.heads["master"]

    topic_a = @source.heads.create("topic_a", master_branch.target_oid, @user)
    commit_a = topic_a.append_commit(metadata, @user) { |f| f.add "file_a", "a" }

    topic_b1 = @source.heads.create("topic_b1", commit_a.oid, @user)
    commit_b = topic_b1.append_commit(metadata, @user) { |f| f.add "file_b", "b" }
    topic_b2 = @source.heads.create("topic_b2", commit_b.oid, @user)

    pr_a = PullRequest.create_for!(@source, base: "master", head: "topic_a", user: @user,
      title: "Merge A to master", body: "A pull request")
    pr_b1 = PullRequest.create_for!(@source, base: "master", head: "topic_b1", user: @user,
      title: "Merge B1 to master", body: "A pull request")
    pr_b2 = PullRequest.create_for!(@source, base: "master", head: "topic_b2", user: @user,
      title: "Merge B2 to master", body: "A pull request")

    [pr_a, pr_b1, pr_b2]
  end

  def get_merged_closed_events(pr)
    pr.events.order(id: :asc)
      .filter { |e| e.event == "merged" || e.event == "closed" }
      .map { |e| { event: e.event, commit_id: e.commit_id, message: e.message } }
  end

  context "Ref update merges multiple pull requests; only some are passing policy" do
    test "Merging approved PR via UI closes 2 unapproved PR's; only approved PR is marked `merged`" do
      # In this scenario, only pr_b1 has been approved. When it is merged, pr_a and pr_b2 should be
      # marked as "closed" not "merged", so that customers don't file bug reports about how "my PR
      # was allowed to merge despite not passing policy".
      (pr_a, pr_b1, pr_b2) = setup_3_pr_test

      # pr_b1 is approved
      create_pr_approval(pr_b1, @reviewer)

      # pr_a failing policies
      pr_a.reload
      pr_a.create_merge_commit
      decision = pr_a.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      # pr_b1 passing policies
      pr_b1.reload
      pr_b1.create_merge_commit
      decision = pr_b1.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # pr_b2 failing policies
      pr_b2.reload
      pr_b2.create_merge_commit
      decision = pr_b2.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      with_enqueued_pr_sync_jobs(additional_jobs: [CreatePullRequestMergeCommitJob]) do
        # pr_a refuses to merge (no approvals)
        merge_result = pr_a.merge(@user, expected_head: @source.heads["topic_a"].target_oid, method: :merge)
        refute merge_result.first

        # pr_b2 refuses to merge (no approvals)
        merge_result = pr_b2.merge(@user, expected_head: @source.heads["topic_b2"].target_oid, method: :merge)
        refute merge_result.first

        # pr_b1 successfully merges
        merge_result = pr_b1.merge(@user, expected_head: @source.heads["topic_b1"].target_oid, method: :merge)
        assert merge_result.first
      end

      # Regardless of FF, all 3 PR's should be closed
      assert pr_a.reload.issue.closed?
      assert pr_b1.reload.issue.closed?
      assert pr_b2.reload.issue.closed?

      # All 3 should be marked as merged; b1's merge commit should be set since it was merged by system
      refute_nil pr_a.merged_at
      assert_nil pr_a.base_sha_on_merge

      refute_nil pr_b1.merged_at
      refute_nil pr_b1.base_sha_on_merge

      refute_nil pr_b2.merged_at
      assert_nil pr_b2.base_sha_on_merge

      # Find all "merged" and "closed" events for each PR timeline
      events_a = get_merged_closed_events(pr_a)
      events_b1 = get_merged_closed_events(pr_b1)
      events_b2 = get_merged_closed_events(pr_b2)

      assert_equal events_a, [
        { event: "closed", commit_id: pr_a.merge_commit_sha, message: "merged_indirectly", },
      ]
      assert_equal events_b1, [
        { event: "merged", commit_id: pr_b1.merge_commit_sha, message: nil, },
        { event: "closed", commit_id: nil, message: nil, },
      ]
      assert_equal events_b2, [
        { event: "closed", commit_id: pr_b2.merge_commit_sha, message: "merged_indirectly", },
      ]
    end

    test "Merging approved PR via direct push closes 2 unapproved PR's; only approved PR is marked `merged`" do
      # In this scenario, only pr_b1 has been approved. When we push a merge commit, pr_a and pr_b2
      # should be marked as "closed" not "merged", so that customers don't file bug reports about how
      # "my PR was allowed to merge despite not passing policy".
      (pr_a, pr_b1, pr_b2) = setup_3_pr_test

      # pr_b1 is approved
      create_pr_approval(pr_b1, @reviewer)

      # pr_a failing policies
      pr_a.reload
      pr_a_merge_commit = pr_a.create_merge_commit
      decision = pr_a.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      # pr_b1 passing policies
      pr_b1.reload
      pr_b1.create_merge_commit
      decision = pr_b1.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # pr_b2 failing policies
      pr_b2.reload
      pr_b2_merge_commit = pr_b2.create_merge_commit
      decision = pr_b2.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      refute_predicate decision, :rules_fulfilled?
      assert_predicate decision, :more_reviews_required?

      with_enqueued_pr_sync_jobs(additional_jobs: [CreatePullRequestMergeCommitJob]) do
        master_branch = @source.heads["master"]

        # Pushing pr_a merge commit fails (no approvals)
        assert_raises Git::Ref::RepositoryRuleViolationError do
          master_branch.update(pr_a_merge_commit, @user)
        end

        # Pushing either pr_b1 or pr_b2 merge commit will succeed. Both are pointing to the same head commit, so the
        # server doesn't distinguish between them. The candidate PR's will always be pr_b1 and pr_b2, of which b1
        # will succeed. For fun, we'll push b2's merge commit.
        master_branch.update(pr_b2_merge_commit, @user)
      end

      # Regardless of FF, all 3 PR's should be closed
      assert pr_a.reload.issue.closed?
      assert pr_b1.reload.issue.closed?
      assert pr_b2.reload.issue.closed?

      # All 3 should be marked as merged; base_sha_on_merge should not be set since it's not a system merge
      refute_nil pr_a.merged_at
      assert_nil pr_a.base_sha_on_merge

      refute_nil pr_b1.merged_at
      assert_nil pr_b1.base_sha_on_merge

      refute_nil pr_b2.merged_at
      assert_nil pr_b2.base_sha_on_merge

      # Find all "merged" and "closed" events for each PR timeline
      events_a = get_merged_closed_events(pr_a)
      events_b1 = get_merged_closed_events(pr_b1)
      events_b2 = get_merged_closed_events(pr_b2)

      assert_equal events_a, [
        { event: "closed", commit_id: pr_a.merge_commit_sha, message: "merged_indirectly", },
      ]
      assert_equal events_b1, [
        { event: "merged", commit_id: pr_b1.merge_commit_sha, message: nil, },
        { event: "closed", commit_id: nil, message: nil, },
      ]
      assert_equal events_b2, [
        { event: "closed", commit_id: pr_b2.merge_commit_sha, message: "merged_indirectly", },
      ]
    end

    test "Merging approved PR via system marks all approved PR's at same commit `merged`" do
      # In this scenario, all 3 PRs are approved. When we merge either pr_b1 or pr_b2, both should
      # be marked as both "merged" and "closed". pr_a is still indirectly merged, because the commit
      # pushed isn't equivalent to its contents.
      (pr_a, pr_b1, pr_b2) = setup_3_pr_test

      # All 3 PR's approved
      create_pr_approval(pr_a, @reviewer)
      create_pr_approval(pr_b1, @reviewer)
      create_pr_approval(pr_b2, @reviewer)

      # pr_a passing policies
      pr_a.reload
      pr_a.create_merge_commit
      decision = pr_a.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # pr_b1 passing policies
      pr_b1.reload
      pr_b1_merge_commit = pr_b1.create_merge_commit
      decision = pr_b1.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # pr_b2 passing policies
      pr_b2.reload
      pr_b2.create_merge_commit
      decision = pr_b2.merge_state(viewer: @user).async_pull_request_review_policy_decision.sync
      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      with_enqueued_pr_sync_jobs(additional_jobs: [CreatePullRequestMergeCommitJob]) do
        @source.heads["master"].update(pr_b1_merge_commit, @user)
      end

      # Regardless of FF, all 3 PR's should be closed
      assert pr_a.reload.issue.closed?
      assert pr_b1.reload.issue.closed?
      assert pr_b2.reload.issue.closed?

      # All 3 should be marked as merged; base_sha_on_merge should not be set since it's not a system merge
      refute_nil pr_a.merged_at
      assert_nil pr_a.base_sha_on_merge

      refute_nil pr_b1.merged_at
      assert_nil pr_b1.base_sha_on_merge

      refute_nil pr_b2.merged_at
      assert_nil pr_b2.base_sha_on_merge

      # Find all "merged" and "closed" events for each PR timeline
      events_a = get_merged_closed_events(pr_a)
      events_b1 = get_merged_closed_events(pr_b1)
      events_b2 = get_merged_closed_events(pr_b2)

      assert_equal events_a, [
        { event: "closed", commit_id: pr_a.merge_commit_sha, message: "merged_indirectly", },
      ]
      assert_equal events_b1, [
        { event: "merged", commit_id: pr_b1.merge_commit_sha, message: nil, },
        { event: "closed", commit_id: nil, message: nil, },
      ]
      assert_equal events_b2, [
        { event: "merged", commit_id: pr_b2.merge_commit_sha, message: nil, },
        { event: "closed", commit_id: nil, message: nil, },
      ]
    end
  end

  context "user pushes a locally-created merge or rebase to source branch" do
    #
    # After PR is approved, user merges master into topic locally and pushes to server. During the interim,
    # someone else has pushed to master, so the merge is actually one commit behind. Given the merge is
    # clean (no new content), the approval should be promoted to the current head and merge base.
    #
    test "when user merges target into source cleanly" do
      metadata = { message: "msg", committer: @user }

      # Turn off branch protection while we build our initial state
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true,
        pull_request_reviews_enforcement_level: :off)

      master_branch = @source.heads["master"]
      local_master_oid = master_branch.target_oid

      pr_base_commit = @source.commits.find(master_branch.target.parent_oids.first)

      topic_branch = @source.heads.create("topic", pr_base_commit.oid, @user)
      topic_commit_a = topic_branch.append_commit(metadata, @user) { |f| f.add "file_1", "1" }

      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # Create PR
      pull = PullRequest.create_for!(@source, base: "master", head: "topic", user: @user,
        title: "A pull request", body: "Boring, I promise")

      pr_merge_base_oid = pull.find_best_merge_base_sha(use_current_base_sha: true)
      assert_equal pr_base_commit.oid, pr_merge_base_oid

      # Add an approval and a change request
      approval = create_pr_approval(pull, @reviewer)
      change_request = create_pr_change_request(pull, @another_reviewer)

      # Reviews are all current
      assert pull.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # Someone else checks into master between user pulling and pushing. Even though user is 1 commit behind
      # the server when they push their merge, approvals should still be promoted
      @protected_branch.update!(pull_request_reviews_enforcement_level: :off)
      remote_master_commit = master_branch.append_commit(metadata, @user) { |f| f.add "file_0", "0" }
      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # User merges master into topic locally, and pushes
      local_merge_commit = @source.commits.create_merge_commit(@user, "topic", local_master_oid).first

      with_enqueued_pr_sync_jobs do

        topic_branch.update(local_merge_commit.oid, @user)
      end

      # Check that commits are all where we expect
      assert_equal local_merge_commit.oid, topic_branch.target_oid
      assert_equal topic_commit_a.oid, local_merge_commit.parent_oids.first
      assert_equal local_master_oid, local_merge_commit.parent_oids.second

      # Approval got promoted
      approval.reload
      assert_equal local_master_oid, approval.merge_base_sha
      assert_equal local_merge_commit.oid, approval.head_sha

      # Non-approvals never get promoted
      change_request.reload
      assert_equal pr_merge_base_oid, change_request.merge_base_sha
      assert_equal topic_commit_a.oid, change_request.head_sha

      # Reviews are all current
      assert pull.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # If the change_request review is dismissed, policy will pass using the approval granted before rebase.
      # (sorbet doesn't seem to understand the args to dismiss!(), so we have to cast it to T.untyped)
      T.cast(change_request, T.untyped).dismiss!(@another_reviewer, message: "dismiss")
      change_request.save!

      pull.reload
      pull.create_merge_commit
      decision = get_check_decision(pull: pull, after_oid: pull.merge_commit_sha, protection: @protected_branch)

      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?

      # Push of new content will dismiss approval; both reviews should now be dismissed
      with_enqueued_pr_sync_jobs do
        topic_commit_b = topic_branch.append_commit(metadata, @user) { |f| f.add "file_2", "2" }
      end

      assert pull.reload.reviews.all?(&:dismissed?)
    end

    #
    # After PR is approved, user does interactive rebase. They squash two commits into one and rebase on
    # current master. During the interim, someone else has pushed to master, so the rebase is actually
    # one commit behind when pushed. The approval should be promoted to the current head and merge base.
    #
    test "when locally rebasing and squashing 2 commits into 1" do

      metadata = { message: "msg", committer: @user }

      # Turn off branch protection while we build our initial state
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true,
        pull_request_reviews_enforcement_level: :off)

      master_branch = @source.heads["master"]
      local_master_oid = master_branch.target_oid

      pr_base_commit = @source.commits.find(master_branch.target.parent_oids.first)

      topic_branch = @source.heads.create("topic", pr_base_commit.oid, @user)
      topic_commit_a = topic_branch.append_commit(metadata, @user) { |f| f.add "file_1", "1" }

      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # Create PR
      pull = PullRequest.create_for!(@source, base: "master", head: "topic", user: @user,
        title: "A pull request", body: "Boring, I promise")

      pr_merge_base_oid = pull.find_best_merge_base_sha(use_current_base_sha: true)
      assert_equal pr_base_commit.oid, pr_merge_base_oid

      # Second commit on topic
      topic_commit_b = T.let(nil, T.nilable(Commit))
      with_enqueued_pr_sync_jobs do

        topic_commit_b = topic_branch.append_commit(metadata, @user) { |f| f.add "file_2", "2" }
      end
      pull.reload

      # Add an approval and a change request
      approval = create_pr_approval(pull, @reviewer)
      change_request = create_pr_change_request(pull, @another_reviewer)

      # Reviews are all current
      assert pull.reload.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # Generate a rebase commit. We won't use this system commit, but we'll use the tree.
      pull.create_merge_commit
      system_merge_commit = @source.commits.find(pull.merge_commit_sha)

      # Someone else checks into master between user pulling and pushing. Even though user is 1 commit behind
      # the server when they push their rebase, approvals should still be promoted
      @protected_branch.update!(pull_request_reviews_enforcement_level: :off)
      remote_master_commit = master_branch.append_commit(metadata, @user) { |f| f.add "file_0", "0" }
      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # User does interactive rebase of topic onto master locally, squashing 2 commits to 1 and pushing
      local_rebase_commit = @source.commits.create(metadata.merge({ tree: system_merge_commit.tree_oid }), local_master_oid)

      with_enqueued_pr_sync_jobs do
        topic_branch.update(local_rebase_commit.oid, @user)
      end
      # Check that commits are all where we expect
      assert_equal local_rebase_commit.oid, topic_branch.target_oid
      assert_equal [local_master_oid], local_rebase_commit.parent_oids

      # Approvals got promoted
      approval.reload
      assert_equal local_master_oid, approval.merge_base_sha
      assert_equal local_rebase_commit.oid, approval.head_sha

      # Non-approvals never get promoted
      change_request.reload
      assert_equal pr_merge_base_oid, change_request.merge_base_sha
      assert_equal topic_commit_b&.oid, change_request.head_sha

      # Reviews are all current
      assert pull.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # If change_request is dismissed, policy will pass using approval granted from before rebase
      # (note that sorbet doesn't seem to know about the args to dismiss!(), so we have to cast it to T.untyped)
      T.cast(change_request, T.untyped).dismiss!(@another_reviewer, message: "dismiss")
      change_request.save!

      pull.reload
      pull.create_merge_commit
      decision = get_check_decision(pull: pull, after_oid: pull.merge_commit_sha, protection: @protected_branch)

      assert_predicate decision, :rules_fulfilled?
      refute_predicate decision, :more_reviews_required?
    end

    #
    # After PR is approved, user merges master into topic locally and pushes to server. The merge pushed
    # to topic doesn't have the same file contents as a system-created merge between master and topic. The
    # approval should be dismissed.
    #
    test "when merge from target into source has modifications" do
      metadata = { message: "msg", committer: @user }

      # Turn off branch protection while we build our initial state
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true,
        pull_request_reviews_enforcement_level: :off)

      master_branch = @source.heads["master"]
      local_master_oid = master_branch.target_oid

      pr_base_commit = @source.commits.find(master_branch.target.parent_oids.first)

      topic_branch = @source.heads.create("topic", pr_base_commit.oid, @user)
      topic_commit_a = topic_branch.append_commit(metadata, @user) { |f| f.add "file_1", "1" }

      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # Create PR
      pull = PullRequest.create_for!(@source, base: "master", head: "topic", user: @user,
        title: "A pull request", body: "Boring, I promise")

      pr_merge_base_oid = pull.find_best_merge_base_sha(use_current_base_sha: true)
      assert_equal pr_base_commit.oid, pr_merge_base_oid

      # Approve PR at commit_a
      approval = create_pr_approval(pull, @reviewer)

      # Reviews are all current
      assert pull.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # User merges master into topic locally, making modification in the process, and pushes
      pull.create_merge_commit
      system_merge_commit = @source.commits.find(pull.merge_commit_sha)

      # (scratch_branch for building a merge commit, since git helpers won't create free-floating commits)
      scratch_branch = @source.heads.create("scratch", topic_commit_a.oid, @user)
      local_changes_commit = scratch_branch.append_commit(metadata, @user) { |f| f.add "changes_during_merge", "X" }

      # Create a local merge commit
      local_merge_commit_oid = @source.create_merge_commit(
        topic_commit_a.oid, local_master_oid,
        { name: "Custom Author Name", email: "Internal email", time: Time.now },
        "Merge commit message",
        { tree: local_changes_commit.tree_oid }
      ).first
      local_merge_commit = @source.commits.find(local_merge_commit_oid)

      # Locally-created merge has correct parents..
      assert_equal topic_commit_a.oid, local_merge_commit.parent_oids.first
      assert_equal local_master_oid, local_merge_commit.parent_oids.second
      # ..but file contents differ from system merge
      refute_equal system_merge_commit.tree_oid, local_merge_commit.tree_oid

      # Approval is good right now
      assert pull.reload.reviews.all?(&:approved?)

      # Push locally-modified merge to topic branch
      with_enqueued_pr_sync_jobs do

        topic_branch.update(local_merge_commit.oid, @user)
      end

      # Approval got dismissed because not tree-equal
      assert pull.reload.reviews.all?(&:dismissed?)
    end

    #
    # After PR is approved, user merges master into topic locally and pushes to server. The user had to
    # resolve merge conflicts to create the merge. The approval should be dismissed.
    #
    test "always dismisses when merge from target into source resolves conflicts" do
      metadata = { message: "msg", committer: @user }

      # Turn off branch protection while we build our initial state
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true,
        pull_request_reviews_enforcement_level: :off)

      master_branch = @source.heads["master"]
      local_master_oid = master_branch.target_oid

      pr_base_commit = @source.commits.find(master_branch.target.parent_oids.first)

      topic_branch = @source.heads.create("topic", pr_base_commit.oid, @user)
      topic_commit_a = topic_branch.append_commit(metadata, @user) { |f| f.add "file_1", "BBBBBBB" }

      # Conflicts:
      master_commit_a = master_branch.append_commit(metadata, @user) { |f| f.add "file_1", "AAAAAAA" }

      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      # Create PR
      pull = PullRequest.create_for!(@source, base: "master", head: "topic", user: @user,
        title: "A pull request", body: "Boring, I promise")

      pr_merge_base_oid = pull.find_best_merge_base_sha(use_current_base_sha: true)
      assert_equal pr_base_commit.oid, pr_merge_base_oid

      # Approve PR at commit_a
      approval = create_pr_approval(pull, @reviewer)

      # Reviews are all current
      assert pull.compute_review_statuses(use_current_base_sha: true).values.all? { |s| s == :current }

      # User merges master into topic locally, making modification in the process, and pushes
      merge_success = pull.create_merge_commit
      refute merge_success

      # User creates a merge commit locally, taking the changes on topic1 and discarding changes on master
      local_merge_commit_oid = @source.create_merge_commit(
        topic_commit_a.oid, master_commit_a.oid,
        { name: "Custom Author Name", email: "Internal email", time: Time.now },
        "Resolved merge conflicts locally",
        { tree: topic_commit_a.tree_oid }
      ).first
      local_merge_commit = @source.commits.find(local_merge_commit_oid)

      # Locally-created merge has correct parents..
      assert_equal topic_commit_a.oid, local_merge_commit.parent_oids.first
      assert_equal master_commit_a.oid, local_merge_commit.parent_oids.second

      # Approval is good right now
      assert pull.reload.reviews.all?(&:approved?)

      # Push locally-modified merge to topic branch
      with_enqueued_pr_sync_jobs do

        topic_branch.update(local_merge_commit.oid, @user)
      end

      # Approval got dismissed because conflicts were resolved during merge
      assert pull.reload.reviews.all?(&:dismissed?)
    end
  end

  context "when PR is closed" do
    test "keeps approval state after merged" do
      @protected_branch.update!(required_approving_review_count: 1, dismiss_stale_reviews_on_push: true)

      # The default pull doesn't have any changes, so we need one to make them tree-different
      with_enqueued_pr_sync_jobs do

        @source.refs[@pull.head_ref].append_commit({ message: "msg", committer: @user }, @user) { |f| f.add "file_1", "1" }
      end

      # Add a valid approval for the latest on the PR head
      @pull.reload
      create_pr_approval(@pull, @reviewer)

      # PR should be approved
      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert decision.rules_fulfilled?

      # Complete a merge
      @pull.merge(@user, message_title: "msg", message: "body")
      @pull.reload

      # The PR should still be passing reviews after merged
      decision = @pull.merge_state(viewer: @user).pull_request_review_policy_decision
      assert decision.rules_fulfilled?
      assert_equal "Changes approved", decision.reason.summary
      refute_predicate decision, :more_reviews_required?
    end
  end

  context "evalaute mode" do
    test "reviews are not dismissed when a rule is in evaluate mode" do
      review = create_pr_approval(@org_pull, @org_reviewer)

      # dismiss is not enabled so we won't dismiss the review
      with_enqueued_pr_sync_jobs do
        @org_repo.refs[@org_pull.head_ref].append_commit({ message: "msg", committer: @org_admin }, @org_admin) { |f| f.add "file_1", "1" }
      end
      @org_pull.reload

      # Require a PR review but do not dismiss reviews
      protected_branch = create(:protected_branch, repository: @org_repo, creator: @org_admin,
        pull_request_reviews_enforcement_level: :everyone, required_approving_review_count: 1)

      # add a rule with dismiss on but in evaluate mode
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org_repo, enforcement: "evaluate")
      rule_config = create(
        :repository_rule_configuration,
        rule_type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          require_code_owner_review: false,
          dismiss_stale_reviews_on_push: true,
          ignore_approvals_from_contributors: false,
          require_last_push_approval: false,
          authorized_dismissal_actors_only: false,
          required_review_thread_resolution: false
        },
        repository_ruleset: ruleset
      )

      decision = get_check_decision_for_rule(pull: @org_pull, after_oid: @org_pull.create_merge_commit,
        rule_configs: [protected_branch.pull_request_policy, rule_config], user: @org_admin)

      # The evaluate rule with dismiss on should not bleed into the non-dismiss enforced rule
      assert decision.rules_fulfilled?

      # ensure the evaluate mode rule fails
      refute decision.rule_decisions[rule_config].rules_fulfilled?
    end
  end
end
