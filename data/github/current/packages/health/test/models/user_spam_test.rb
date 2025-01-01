# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSpamTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  fixtures do
    @spamurai = create :staff_admin_user
    free    = GitHub::Plan.find!("free")
    @user   = create(:user)
    @owner  = create(:user, plan: free)
    create(:repository, name: "hax", pushed_at: Time.now, created_at: (Time.now - 60), owner: @owner)
    @notified_user = create(:user, plan: free)
    create(:repository, name: "camelopardus", pushed_at: Time.now, created_at: (Time.now - 60), owner: @notified_user)
    Issue.create(
      repository_id: @notified_user.repositories.first.id,
      user_id: @user.id,
      title: "Issue from a spammer",
    )
    @repo = create(:repository, has_discussions: true)
    @issue = create :issue, repository: @repo, user: @user

    @user.emails.last.verify!
    @user = User.find(@user.id)
    @discussion = create(:discussion, user: @user, repository: @repo)
    @discussion_comment = create(:discussion_comment, user: @user, repository: @repo,
      discussion: @discussion)

    setup_staff_user
  end

  setup do
    GitHub.cache.allow = nil
    GitHub.cache.clear
  end

  context "#mark_as_spammy" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    end

    test "works" do
      @user.mark_as_spammy
      assert @user.spammy?
    end

    test "returns nil when user is already flagged" do
      @user.mark_as_spammy
      refute @user.mark_as_spammy
    end

    test "employees cannot be flagged as spammy" do
      staffer = create(:staff_admin_user)
      assert_predicate staffer, :employee?
      refute_predicate staffer, :hammy?

      marked_as_spammy = staffer.mark_as_spammy(reason: "stop all your spamming")
      refute staffer.reload.spammy?
      refute marked_as_spammy
    end

    context "instruments" do
      test "when a user is marked as spammy" do
        Timecop.freeze do
          GitHub.stubs(:hydro_enabled?).returns(true)

          events = subscribe "staff.mark_as_spammy"
          reason = "Did spammy things: https://github.com/best/spam"
          staffer = create :staff_admin_user
          GitHub.hydro_publisher.expects(:publish).at_least_once.returns(Hydro::Sink::Result.success)
          @user.mark_as_spammy actor: staffer, reason: reason

          expected_payload = {
            user:                      @user.login,
            user_id:                   @user.id,
            user_type:                 "User",
            reason:                    "#{reason} by @#{staffer.login}",
            previously_spammy:         false,
            currently_spammy:          true,
            origin:                    :DOTCOM,
            spammy_classification:     "analyst-0",
            spammy_classifier_type:    "analyst",
            spammy_classifier_id:      0,
            subject:                   "unknown",
            staff_actor:               staffer.login,
            staff_actor_id:            staffer.id,
            actor:                     User.staff_user.to_s,
            actor_id:                  User.staff_user.id,
            hard_flag:                 nil,
          }

          assert event = events.pop, "a staff.mark_as_spammy event was expected"
          assert_equal "staff.mark_as_spammy", event.name
          assert_equal expected_payload, event.payload
        end
      end

      test "when an org is marked as spammy" do
        Timecop.freeze do
          GitHub.stubs(:hydro_enabled?).returns(true)

          events = subscribe "staff.mark_as_spammy"
          reason = "Did spammy things: https://github.com/best/spam"
          staffer = create :staff_admin_user
          org = create :organization
          GitHub.hydro_publisher.expects(:publish).at_least_once.returns(Hydro::Sink::Result.success)
          org.mark_as_spammy actor: staffer, reason: reason

          expected_payload = {
            org:                       org.login,
            org_id:                    org.id,
            user_type:                 "Organization",
            reason:                    "#{reason} by @#{staffer.login}",
            previously_spammy:         false,
            currently_spammy:          true,
            origin:                    :DOTCOM,
            spammy_classification:     "analyst-0",
            spammy_classifier_type:    "analyst",
            spammy_classifier_id:      0,
            subject:                   "unknown",
            staff_actor:               staffer.login,
            staff_actor_id:            staffer.id,
            actor:                     User.staff_user.to_s,
            actor_id:                  User.staff_user.id,
            hard_flag:                 nil,
          }

          assert event = events.pop, "a staff.mark_as_spammy event was expected"
          assert_equal "staff.mark_as_spammy", event.name
          assert_equal expected_payload, event.payload
        end
      end
    end

    test "publishes abuse classification hydro event" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"
        user_to_investigate = create :user, login: "spammertime"

        user_to_investigate.mark_as_spammy(actor: analyst, reason: "sketchy")

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          account: Hydro::EntitySerializer.user(user_to_investigate),
          previous_classification: :NONE,
          current_classification: :SPAMMY,
          previous_spammy_reason: { value: "" },
          current_spammy_reason: { value: "sketchy by @triage-worker" },
          previously_suspended: { value: false },
          currently_suspended: { value: false },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published(message, schema: "github.v1.AbuseClassification")
        assert_hydro_messages count: 1, schema: "github.v1.AbuseClassification"
      end
    end

    test "removes notifications derived from spammy user issues" do
      response = GitHub.newsies.web.count(@notified_user)
      assert_equal response, 0
    end

    test "recalculates followees followers_count" do
      @user.follow(@owner)
      assert_equal 1, User.find(@owner.id).followers_count(viewer: nil)

      only = [CalculateFolloweringsCountJob, UpdateTableUserHiddenJob]
      perform_enqueued_jobs(only: only) { @user.mark_as_spammy }
      assert_equal 0, User.find(@owner.id).followers_count(viewer: nil)
    end

    test "recalculates followers following_count" do
      other_user = create(:user)
      @owner.follow(@user)
      @owner.follow(other_user)
      @user.follow(@owner)
      @user.follow(other_user)
      other_user.follow(@user)
      other_user.follow(@owner)

      assert_equal 2, User.find(@owner.id).followers_count(viewer: nil)
      assert_equal 2, User.find(@owner.id).following_count(viewer: nil)
      assert_equal 2, User.find(@user.id).followers_count(viewer: nil)
      assert_equal 2, User.find(@user.id).following_count(viewer: nil)

      only = [CalculateFolloweringsCountJob, UpdateTableUserHiddenJob]
      perform_enqueued_jobs(only: only) { @user.mark_as_spammy }

      assert_equal 0, User.find(@user.id).followers_count(viewer: nil),
        "spammy user followers_count resets to zero"
      assert_equal 0, User.find(@user.id).following_count(viewer: nil),
        "spammy user following_count resets to zero"
      assert_equal 1, User.find(@owner.id).followers_count(viewer: nil),
        "spammy user not included in followers_count"
      assert_equal 1, User.find(@owner.id).following_count(viewer: nil),
        "spammy user not included in following_count"
    end

    test "marks stars spammy" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        repo = create(:repository)
        @user.star(repo)

        refute repo.stars.last.user_hidden?
        @user.mark_as_spammy
        assert repo.stars.last.user_hidden?, "Did not mark star as user_hidden?"
      end
    end

    test "recalculates stargazer counts" do
      only = [CalculateStarsCountJob, UpdateTableUserHiddenJob]
      perform_enqueued_jobs(only: only) do
        repo = create(:repository)
        @user.star(repo)

        assert_equal 1, repo.reload.stargazer_count

        @user.mark_as_spammy
        assert_equal 0, repo.reload.stargazer_count
      end
    end

    test "marks issues as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        refute @user.issues.last.user_hidden?, "Issues should not be marked as user_hidden? after creation"

        @user.mark_as_spammy
        assert @user.issues.last.user_hidden?, "Did not mark issue as user_hidden?"
      end
    end

    test "marks discussions as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        refute_predicate @user.discussions.last, :user_hidden?,
        "Discussions should not be marked as user_hidden? after creation"

        @user.mark_as_spammy
        assert_predicate @user.discussions.last, :user_hidden?, "Did not mark discussion as user_hidden?"
      end
    end

    test "marks discussion comments as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        refute_predicate @user.discussion_comments.last, :user_hidden?,
        "Discussion comments should not be marked as user_hidden? after creation"

        @user.mark_as_spammy
        assert_predicate @user.discussion_comments.last, :user_hidden?, "Did not mark discussion comment as user_hidden?"
      end
    end

    test "marks issue comments as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        issue_comment = create(:issue_comment, issue: @issue,  user: @user)

        refute @user.issue_comments.last.user_hidden?, "Issue comments should not be marked as user_hidden? after creation"

        @user.mark_as_spammy
        assert @user.issue_comments.last.user_hidden?, "Did not mark issue comment as user_hidden?"
      end
    end

    test "marks commit comments as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        commit_comment = create(:commit_comment,
                                repository: @repo,
                                user: @user,
                                path: "color.js",
                                commit_id: "3572d83ba062076f6a740379463d0f3f770d7fc5",
                               )

        refute @user.commit_comments.last.user_hidden?, "Commit comments should not be marked as user_hidden? after creation"

        @user.mark_as_spammy
        assert @user.commit_comments.last.user_hidden?, "Did not mark commit comment as user_hidden?"
      end
    end

    test "marks pull request review comments as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        @owner = create(:user, plan: "micro")
        @forker = create(:user)

        @source = create(:private_repository, owner: @owner, from_example: :review_comment_source)
        @source.add_member @forker, action: :write

        @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

        @issue = create(:issue, user: @forker, repository: @source)

        @pull = PullRequest.create_for(@source,
                                       base: "master",
                                       head: "#{@fork.user}:topic",
                                       user: @issue.user,
                                       issue: @issue)
        @issue.pull_request = @pull

        review = @pull.reviews.create!(
          user: @forker,
          head_sha: @pull.head_sha,
        )

        comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @forker,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "ship it",
          pull_request_review_id: review.id,
        )

        refute T.must(review.review_comments.first).user_hidden?, "Pull request review comments should not be marked as user_hidden? after creation"
        @forker.mark_as_spammy
        assert T.must(review.review_comments.first).user_hidden?, "Did not mark pull request review comment as user_hidden?"
      end
    end

    test "marks pull request reviews as user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        @owner = create(:user, plan: "micro")
        @forker = create(:user)

        @source = create(:private_repository, owner: @owner, from_example: :review_comment_source)
        @source.add_member @forker, action: :write

        @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

        @issue = create(:issue, user: @forker, repository: @source)

        @pull = PullRequest.create_for(@source,
                                       base: "master",
                                       head: "#{@fork.user}:topic",
                                       user: @issue.user,
                                       issue: @issue)
        @issue.pull_request = @pull

        review = @pull.reviews.create!(
          user: @forker,
          head_sha: @pull.head_sha,
        )

        comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @forker,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "ship it",
          pull_request_review_id: review.id,
        )

        review.approve!

        refute T.must(@pull.reviews.first).user_hidden?, "Pull request review should not be marked as user_hidden? after creation"
        @forker.mark_as_spammy
        assert T.must(@pull.reviews.first).user_hidden?, "Did not mark pull request review as user_hidden?"
      end
    end

    test "enqueues a SuspendDependentCodespacesJob when the codespaces_handle_spammy_users flag is set to true" do
      Codespaces::SuspendDependentCodespacesJob.expects(:perform_later).with(owner_id: @user.id)
      @user.mark_as_spammy
    end

    test "enqueues a SuspendDependentCodespacesJob with the org info" do
      org = create(:organization)
      Codespaces::SuspendDependentCodespacesJob.expects(:perform_later).with(owner_id: org.id)
      org.mark_as_spammy
    end
  end

  context "#mark_not_spammy" do
    test "increments false positive counts for flaggable patterns" do
      user = create :user, login: "bob"

      flag_pattern = SpamPattern.create(class_name: User, flag: true,
                                        attribute_name: "login",
                                        pattern: /bob/)

      log_pattern = SpamPattern.create(class_name: User, flag: false,
                                       log: true, attribute_name: "login",
                                       pattern: /b/)

      assert flag_pattern.matches?(user)
      assert log_pattern.matches?(user)
      assert_equal 2, SpamPattern.matches_for(user).size
      assert_equal 1, SpamPattern.flag_matches_for(user).size

      flag_pattern.record_match!
      log_pattern.record_match!
      user.mark_as_spammy
      user.mark_not_spammy

      assert_equal 1, flag_pattern.reload.false_positives
      assert_equal 0, log_pattern.reload.false_positives
    end

    test "publishes abuse classification hydro event" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"
        user_to_investigate = create :user, login: "spammertime"

        user_to_investigate.mark_as_spammy(reason: "sketchy")
        user_to_investigate.mark_not_spammy(actor: analyst)

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          account: Hydro::EntitySerializer.user(user_to_investigate),
          previous_classification: :SPAMMY,
          current_classification: :NONE,
          previous_spammy_reason: { value: "sketchy" },
          current_spammy_reason: { value: "" },
          previously_suspended: { value: false },
          currently_suspended: { value: false },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published(message, schema: "github.v1.AbuseClassification")
        assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
      end
    end

    test "publishes abuse classification hydro event for hammy classifications" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"
        user_to_investigate = create :user, login: "spammertime"

        user_to_investigate.mark_as_spammy(reason: "sketchy")
        user_to_investigate.mark_not_spammy(actor: analyst, whitelist: true)

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          account: Hydro::EntitySerializer.user(user_to_investigate),
          previous_classification: :SPAMMY,
          current_classification: :HAMMY,
          previous_spammy_reason: { value: "sketchy" },
          current_spammy_reason: { value: "Not spammy" },
          previously_suspended: { value: false },
          currently_suspended: { value: false },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published(message, schema: "github.v1.AbuseClassification")
        assert_hydro_messages count: 2, schema: "github.v1.AbuseClassification"
      end
    end

    test "clears spamminess without whitelisting the user" do
      @user.mark_as_spammy
      assert @user.spammy?
      @user.mark_not_spammy
      refute_predicate @user, :spammy?
      refute_predicate @user, :hammy?
    end

    test "with whitelist true clears spamminess and whitelists the user" do
      @user.mark_as_spammy
      assert @user.spammy?
      @user.mark_not_spammy(whitelist: true)
      refute_predicate @user, :spammy?
      assert_predicate @user, :hammy?
    end

    test "resets trade screening status to not_screened if current status is spammy" do
      profile = create(:account_screening_profile, :with_spammy_status)
      user = profile.user
      user.mark_as_spammy

      assert user.spammy?
      assert_predicate profile, :spammy?

      user.mark_not_spammy
      refute_predicate user, :spammy?
      assert_predicate profile, :not_screened?
    end

    test "marks stars not spammy" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        repo = create(:repository)
        @user.star(repo)

        refute repo.stars.last.user_hidden?
        @user.mark_as_spammy
        assert repo.stars.last.user_hidden?, "Did not mark star as hidden"

        @user.mark_not_spammy
        refute repo.stars.last.user_hidden?, "Did not mark star as non hidden"
      end
    end

    test "recalculates stargazer counts" do
      only = [CalculateStarsCountJob, UpdateTableUserHiddenJob]
      perform_enqueued_jobs(only: only) do
        @user.mark_as_spammy # make user spammy before starring to ensure star goes through but count stays the same
        repo = create(:repository)
        assert @user.can_star?(repo), "spammy user should still be able to star repo"

        assert_difference(-> { Star.count }) do
          @user.star(repo)
        end

        assert_equal 0, repo.reload.stargazer_count,
          "stargazer_count should not have been incremented for spammy star"

        @user.mark_not_spammy
        assert_equal 1, repo.reload.stargazer_count
      end
    end

    test "marks issues as not user hidden" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user = create :user, spammy: true
        repo = create(:repository)
        issue = create :issue, repository: repo, user: user

        assert user.issues.last.user_hidden?

        user.mark_not_spammy
        refute user.issues.last.user_hidden?, "Did not mark issue as non hidden"
      end
    end
  end

  context "#permit_deletion?" do
    test "when the user is not spammy" do
      assert(@user.permit_deletion?(@user), "user unable to delete themselves")
      staffer = create(:staff_admin_user)
      assert(@user.permit_deletion?(staffer), "staff unable to delete user")
    end

    test "when the user is spammy" do
      @user.mark_as_spammy
      refute(@user.permit_deletion?(@user), "user able to delete themselves")
      staffer = create(:staff_admin_user)
      assert(@user.permit_deletion?(staffer), "staff unable to delete user")
    end
  end

  context "tainted_logins" do
    test "deleting spammy user marks login as tainted" do
      Spam.clear_tainted_login(@user.login)
      @user.mark_as_spammy
      assert !Spam.login_is_tainted?(@user.login), "#{@user.login} should not have been on tainted list"
      @user.destroy
      assert Spam.login_is_tainted?(@user.login), "#{@user.login} should have been on tainted list"
      Spam.clear_tainted_login(@user.login)
    end

    test "cannot rename spammy login" do
      @user.mark_as_spammy
      @user.rename(@user.login + "_new")
      refute @user.rename!(@user.login + "_new"), "#{@user.login} is spammy and cannot rename themselves"
    end

    test "creating user with tainted login flags it as spammy" do
      login = "naughtyuser3133t"
      Spam.mark_login_tainted(login)
      assert Spam.login_is_tainted?(login), "#{login} should have been on tainted list"
      user = perform_enqueued_jobs(only: CheckForSpamJob) do
        create(:user, login: login)
      end
      assert user.reload.spammy?
      Spam.clear_tainted_login(@user.login)
    end

    test "tainted logins are case-insensitive" do
      login = "FluffyBunny1234"
      Spam.mark_login_tainted(login)
      assert Spam.login_is_tainted?(login.downcase)
      Spam.clear_tainted_login(@user.login)
    end
  end

  context "#never_spammy?" do
    test "returns true when spam check is disabled" do
      skip "spamminess checks are not enabled on Enterprise" if GitHub.spamminess_check_enabled?
      assert_nil @user.mark_as_spammy

      @user.update!(spammy: true)
      @user.reload
      assert @user.never_spammy?
    end
  end

  context "#mark_as_hammy" do
    test "marks account not spammy and allowlists account" do
      refute_predicate @user, :hammy?
      @user.mark_as_hammy
      assert_predicate @user, :hammy?
      assert_nil @user.mark_as_spammy
      refute_predicate @user, :spammy?
    end
  end

  context "#hydro_spammy_and_suspended_data" do
    test "returns a hash of Hydro data about the user's spammy and suspended statuses" do
      spammy_classification = Hydro::EntitySerializer.account_spammy_classification(@user)
      spammy_reason = Hydro::EntitySerializer.account_spammy_reason(@user)
      suspended_status = Hydro::EntitySerializer.account_suspended(@user)

      result = @user.hydro_spammy_and_suspended_data

      assert_same_elements %i(
        serialized_previous_classification
        serialized_previous_spammy_reason
        serialized_previously_suspended
      ), result.keys
      assert_equal spammy_classification, result[:serialized_previous_classification]
      assert_equal spammy_reason, result[:serialized_previous_spammy_reason]
      assert_equal suspended_status, result[:serialized_previously_suspended]
    end
  end

  context "#instrument_abuse_classification_publish" do
    test "publishes a Hydro event with given data overriding some defaults", skip_enterprise: true do
      actor = create(:user)
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(actor),
        account: Hydro::EntitySerializer.user(@user),
        previous_classification: :NONE,
        current_classification: :NONE,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "" },
        previously_suspended: { value: false },
        currently_suspended: { value: false },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :QUEUE_ACTION_NONE,
        queue_entry: nil,
        previous_queue: nil,
        current_queue: nil,
        queued_time_in_seconds: nil,
      }

      @user.instrument_abuse_classification_publish(actor: actor)

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 1, schema: "github.v1.AbuseClassification"
    end
  end

  context "CheckForSpamJob" do
    test "is enqueued when login attribute changes" do
      CheckForSpamJob.expects(:enqueue).with(@user, {})
      @user.update! login: "willy-nelson"
    end

    test "is enqueued on initial creation" do
      user = build(:user)

      # build :user, adds an email, which creates a UserEmail, which
      # queues this job up as well.
      CheckForSpamJob.expects(:enqueue).with(user)
      CheckForSpamJob.expects(:enqueue).with(user, {})

      user.save
    end
  end
end
