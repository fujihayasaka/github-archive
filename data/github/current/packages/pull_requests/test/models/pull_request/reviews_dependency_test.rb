# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user

    @repo = create :repository, owner: @org, from_example: :rebase_pull_request

    @pull_team = create :team, organization: @org, permission: "pull"
    @push_team = create :team, organization: @org, permission: "push"
    @pull_team.add_repository @repo, :pull
    @push_team.add_repository @repo, :push

    @member = create(:user)
    @push_team.add_member @member, adder: @user

    @readonly_member = create(:user)
    @pull_team.add_member @readonly_member, adder: @user

    @pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue,
        repository: @repo, user: @user,
      )

    @rando = create(:user)
  end

  context "#pending_review_for" do
    test "does not touch the pull request object when creating a new pending review" do
      # ensure the updated_at time stamp is sufficiently in the past
      Timecop.freeze(5.minutes.ago) do
        @pull.save!
      end

      assert_equal @user.pull_request_reviews.count, 0

      assert_no_difference -> { @pull.reload.updated_at } do
        @pull.pending_review_for(user: @user)
      end

      assert_equal @user.reload.pull_request_reviews.count, 1
    end
  end

  context "PullRequest#latest_pending_review_for" do
    test "returns the user's latest pending review" do
      review1 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review1.approve!

      pending = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      assert_predicate pending, :pending?

      review2 = @pull.reviews.build(user: @member, head_sha: @pull.head_sha, repository: @pull.repository)
      review2.save(validate: false) # skip validations to get to pending state
      review2.request_changes!

      create(:pull_request_review, pull_request: @pull, user: create(:user), head_sha: @pull.head_sha)

      assert_equal pending, @pull.latest_pending_review_for(@member)
    end

    test "returns review for the right user" do
      pending1 = create(:pull_request_review, pull_request: @pull, user: @user, head_sha: @pull.head_sha)
      assert_predicate pending1, :pending?

      pending2 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      assert_predicate pending2, :pending?

      assert_equal pending1, @pull.latest_pending_review_for(@user)
      assert_equal pending2, @pull.latest_pending_review_for(@member)
    end
  end

  context "#latest_non_pending_review_for" do
    test "returns the latest non pending review for a user" do
      review1 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review1.approve!

      review2 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review2.approve!

      review3 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review3.approve!

      pending = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      assert_predicate pending, :pending?

      assert_equal review3, @pull.latest_non_pending_review_for(@member)
    end

    test "returns the latest non pending review for the right user" do
      review1 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review1.approve!

      review2 = create(:pull_request_review, pull_request: @pull, user: @readonly_member, head_sha: @pull.head_sha)
      review2.approve!

      pending = create(:pull_request_review, pull_request: @pull, user: @readonly_member, head_sha: @pull.head_sha)
      assert_predicate pending, :pending?

      assert_equal review1, @pull.latest_non_pending_review_for(@member)
      assert_equal review2, @pull.latest_non_pending_review_for(@readonly_member)
      refute @pull.latest_non_pending_review_for(@user)
    end
  end

  context "PullRequest#latest_enforced_review_for" do
    test "returns most recent review that affects mergeability" do
      review1 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review1.approve!

      review2 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review2.comment!

      assert_equal review1, @pull.latest_enforced_review_for(@member)
    end

    test "does not return review if user is nil" do
      review1 = create(:pull_request_review, pull_request: @pull, user: @member, head_sha: @pull.head_sha)
      review1.approve!

      assert_nil @pull.latest_enforced_review_for(nil)
    end
  end

  context "PullRequest#latest_enforced_reviews" do
    test "returns the most recent accepted and rejected reviews per user" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      user_1_review_1.approve!

      Timecop.travel(10) do
        user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_2.id,
        )
        user_1_review_2.request_changes!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        user_2_review_1.approve!

        assert_same_elements [user_1_review_2, user_2_review_1], @pull.latest_enforced_reviews(writers_only: true)
      end
    end

    test "does not return comment reviews" do
      review = create(:pull_request_review, pull_request: @pull, user: @user, head_sha: @pull.head_sha)
      create(:pull_request_review_comment,
        pull_request: @pull,
        commit_id: @pull.head_sha,
        path: "README",
        position: 1,
        pull_request_review_id: review.id,
      )
      review.comment!

      assert_same_elements [], @pull.latest_enforced_reviews(writers_only: true)
    end

    test "returns reviews whose authors are writers on the repository" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo)

      review1 = create(:pull_request_review, pull_request: pull, user: @member, head_sha: pull.head_sha)
      review1.approve!

      review2 = create(:pull_request_review, pull_request: pull, user: @readonly_member, head_sha: pull.head_sha)
      review2.approve!

      assert_same_elements [review1], pull.latest_enforced_reviews(writers_only: true)
    end
  end

  context "PullRequest#latest_enforced_reviews_count_for" do
    test "count for review returns a list of reviews" do
      pull = create(:pull_request, :disable_disk_access, repository: @repo)

      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @member, state: PullRequestReview.state_value(:approved))
      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @member, state: PullRequestReview.state_value(:changes_requested))

      assert_equal 0, pull.latest_enforced_reviews_count_for(:approved)
      assert_equal 1, pull.latest_enforced_reviews_count_for(:changes_requested)

      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @member, state: PullRequestReview.state_value(:dismissed))
      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @member, state: PullRequestReview.state_value(:commented))
      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @readonly_member, state: PullRequestReview.state_value(:approved))
      create(:pull_request_review, pull_request: pull, head_sha: "DEADBEEF" * 5, user: @member, state: PullRequestReview.state_value(:approved))

      assert_equal 1, PullRequest.find(pull.id).latest_enforced_reviews_count_for(:approved)
    end
  end

  context "PullRequest#allows_non_comment_reviews_from?" do
    test "returns false for the pull request creator" do
      refute @pull.allows_non_comment_reviews_from?(reviewer: @pull.user)
    end

    if GitHub.code_review_limits_enabled?
      test "returns true for a drive-by user without approval restrictions on the repo" do
        assert @pull.allows_non_comment_reviews_from?(reviewer: @rando)
      end

      test "returns false for a drive-by user when approval restrictions are enabled on the repo" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)

        refute @pull.allows_non_comment_reviews_from?(reviewer: @rando)
      end

      test "returns true for a drive-by user when approval restrictions are enabled but the feature is disabled" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)

        assert @pull.allows_non_comment_reviews_from?(reviewer: @rando)
      end unless GitHub.code_review_limits_enabled?

      test "returns true for a member with write permissions when approval restrictions are enabled on the repo" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)

        assert @pull.allows_non_comment_reviews_from?(reviewer: @member)
      end

      test "returns false for a bot user not installed on the repo when feature enabled and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        bot = make_integration_installation(target: @rando).bot

        refute @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns false for a bot user with insufficient permissions when feature enabled and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        bot = make_integration_installation(
          repository: @pull.repository,
          permissions: { metadata: :read },
        ).bot

        refute @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns true for a bot user installed on the repo when feature enabled and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        bot = make_integration_installation(
          repository: @pull.repository,
          permissions: { pull_requests: :read },
        ).bot

        assert @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns true for a bot user installed on the repo's owner when feature enabled and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        bot = make_integration_installation(
          target: @pull.repository.owner,
          permissions: { pull_requests: :read },
        ).bot

        assert @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns false for a bot user installed on the repo's owner but not this repo when feature enabled and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        other_repo = create(:repository, owner: @pull.repository.owner)
        bot = make_integration_installation(
          target: @pull.repository.owner,
          repository: other_repo,
        ).bot

        refute @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns true for a bot user not installed on the repo when feature enabled and approval restrictions are off" do
        bot = make_integration_installation(target: @rando).bot

        assert @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end

      test "returns true for a bot user not installed on the repo when flag is off and approval restrictions are on" do
        @pull.repository.restrict_non_comment_pull_request_reviews(actor: @user)
        bot = make_integration_installation(target: @rando).bot

        assert @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end unless GitHub.code_review_limits_enabled?

      test "returns true for a bot user not installed on the repo when flag is off and approval restrictions are off" do
        bot = make_integration_installation(target: @rando).bot

        assert @pull.allows_non_comment_reviews_from?(reviewer: bot)
      end unless GitHub.code_review_limits_enabled?
    end
  end

  context "PullRequest#async_latest_reviews_preferring_opinionated_reviews" do
    test "returns latest reviews by user" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.approve!

      Timecop.travel(10) do
        user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_2.id,
        )
        assert user_1_review_2.request_changes!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        assert user_2_review_1.approve!

        assert_same_elements [user_1_review_2, user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end

    test "returns latest reviews by user, preferring opinionated reviews over commenting ones made later" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.approve!

      user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_2.comment!

      Timecop.travel(10) do
        user_1_review_3 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_3.id,
        )
        assert user_1_review_3.comment!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        assert user_2_review_1.approve!

        assert_same_elements [user_1_review_1, user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end

    test "returns latest reviews by user, preferring opinionated reviews, unless they are dismissed" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.approve!

      user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_2.comment!

      assert user_1_review_1.dismiss!(user_1, message: "dismissing")

      Timecop.travel(10) do
        user_1_review_3 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_3.id,
        )
        user_1_review_3.comment!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        user_2_review_1.comment!

        assert_same_elements [user_1_review_3, user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end

    test "returns the latest commenting review if there are no overriding opinionated ones" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.comment!

      Timecop.travel(10) do
        user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_2.id,
        )
        user_1_review_2.comment!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        user_2_review_1.approve!

        assert_same_elements [user_1_review_2, user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end

    test "returns the latest review unless the user has an outstanding review request" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_1, adder: @user)
      @push_team.add_member(user_2, adder: @user)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.approve!

      Timecop.travel(10) do
        user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_2.id,
        )
        user_1_review_2.comment!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        user_2_review_1.approve!

        assert @pull.request_review_from(reviewers: [user_1], actor: user_2)

        assert_same_elements [user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end

    test "returns the latest reviews, including reviewers without write access" do
      user_1 = create(:user)
      user_2 = create(:user)
      @push_team.add_member(user_2, adder: @user)
      refute @pull.repository.pushable_by?(user_1)
      assert @pull.repository.pushable_by?(user_2)

      user_1_review_1 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
      assert user_1_review_1.approve!

      Timecop.travel(10) do
        user_1_review_2 = create(:pull_request_review, pull_request: @pull, user: user_1, head_sha: @pull.head_sha)
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: user_1,
          commit_id: @pull.head_sha,
          path: "README",
          position: 1,
          pull_request_review_id: user_1_review_2.id,
        )
        user_1_review_2.comment!

        user_2_review_1 = create(:pull_request_review, pull_request: @pull, user: user_2, head_sha: @pull.head_sha)
        user_2_review_1.approve!

        assert_same_elements [user_1_review_1, user_2_review_1], @pull.async_latest_reviews_preferring_opinionated_reviews(user_1).sync
      end
    end
  end
end

class PullRequestAsyncStatusAtMergeTest < GitHub::TestCase
  fixtures do
    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)
    @issue = create(:issue, user: @bwalsh, repository: @source)

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)

    create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "ci/janky", state: "pending")
    create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "ci/janky", state: "success")

    @check_suite = create(:check_suite, repository: @pull.repository, head_sha: @pull.head_sha)
    create(:completed_check_run, check_suite: @check_suite, name: "check_run1")
    create(:completed_check_run, check_suite: @check_suite, name: "check_run2")

    Timecop.travel do
      Timecop.travel(10)

      create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "continuous-integration/travis-ci/pr", state: "success")

      Timecop.travel(10)

      create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "continuous-integration/travis-ci/push", state: "pending")

      Timecop.travel(10)

      @pull.merge

      create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "ci/janky-new", state: "pending")
      create(:status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "ci/janky", state: "failure")

      @pull.reload
    end
  end

  test "returns a list of active statuses for each context before the merge" do
    combined_status = @pull.async_status_at_merge.sync
    statuses = combined_status.status_checks
    assert_equal 5, statuses.size

    # statuses
    assert_equal "continuous-integration/travis-ci/push", statuses[0].context
    assert_equal "pending", statuses[0].state

    assert_equal "continuous-integration/travis-ci/pr", statuses[1].context
    assert_equal "success", statuses[1].state

    assert_equal "ci/janky", statuses[2].context
    assert_equal "success", statuses[2].state

    # check runs
    check_run1_status = statuses.detect { |status| status.context == "check_run1" }
    assert_equal "check_run1", check_run1_status.name
    assert_equal "success", check_run1_status.conclusion

    check_run2_status = statuses.detect { |status| status.context == "check_run2" }
    assert_equal "check_run2", check_run2_status.name
    assert_equal "success", check_run2_status.conclusion
  end
end
