# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/pull_requests"

class PullRequestReviewCommentTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include HydroTestHelpers
  include NewsiesHelper
  include AuditLog::IntegrationTestHelpers
  include PullRequestSynchronizationTestHelpers

  ROLES = GitHub::MinimizeComment::ROLES

  mention_limit = GitHub::HTML::MentionFilter::MENTION_LIMIT

  fixtures do
    Spokesd.enable_spokesd

    @ari = create(:user, login: "ari")
    @spammer = create(:user, login: "spammer", spammy: true)
    @source = create(:repository, owner: @ari, from_example: :review_comment_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :review_comment_fork)
    @author = create(:user)
    @maintainer = create(:user)
    @contributor = create(:user)
    @source.add_member(@contributor, action: :read)
    @source.add_member(@maintainer, action: :write)
    @staff_user = create(:staff_admin_user)
    @source.add_member @bwalsh

    @issue = create(:issue, user: @bwalsh, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @bwalsh,
      )
    @issue.pull_request = @pull

    @users = (0..(mention_limit + 5)).map { |i| create :user, login: "user#{i}" }
    @users.first.watch_repo @source
    @users.last.watch_repo @source

    @steve = create(:paid_user, login: "steve")
    @john = create(:paid_user, login: "john")
    @private_source = create(:private_repository, name: "sekret", owner: @steve, from_example: :review_comment_source)

    @private_source.add_member @john
    @private_fork = create(:fork_repository, forker: @john, fork_repo: @private_source, from_example: :review_comment_fork)

    @private_issue = create(:issue, user: @john, repository: @private_source)
    @private_pull =
      create(:pull_request,
        repository: @private_source,
        base_repository: @private_source,
        base_user: @private_source.owner,
        base_ref: "master",
        head_repository: @private_fork,
        head_user: @private_fork.owner,
        head_ref: "topic",
        issue: @private_issue,
        user: @john,
      )

    example_repo_snapshot

    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration)

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)

    refute_nil @actions_app
  end

  setup_once { disable_monolith_rate_limiter_redis }
  teardown_once { enable_monolith_rate_limiter_redis }

  setup do
    @expected_diff_hunk =
    (<<-DIFF).b.gsub(/^ {4}/, "").strip
    @@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising
     and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun
     Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero
     stories to become a humor title. Aquaman's feature moved to Adventure Comics
    -#103-284 (April 1946 - May 1961) as a backup to the comic book's star, Superboy.
    +#103-284 (April 1946 - May 1961) as a backup to the comic book's star, SUPERBOY.
    DIFF

    example_repo_restore
    disable_feature_flag(:login_revocation_for_credential_in_url)
    disable_feature_flag(:token_scanning_scan_all_token_types_public)

    Spokesd.enable_spokesd
    Repository.any_instance.stubs(:disable_spokes_api_conversions).returns(true)
  end

  test "sorted_by scope returns pull_request_review_comments sorted by date and id " do
    user = create(:user)
    date = Date.new(2016, 2, 3)
    comment1 = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: date
      )
    comment2 = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: date
      )

    assert_equal date, comment1.created_at.to_date
    assert_equal date, comment2.created_at.to_date
    assert comment1.id < comment2.id

    comments = PullRequestReviewComment.sorted_by("created_at", "asc")
    assert_equal comment1.id, comments.first&.id
    assert_equal comment2.id, comments.last&.id

    comments = PullRequestReviewComment.sorted_by("created_at", "desc")
    assert_equal comment1.id, comments.last&.id
    assert_equal comment2.id, comments.first&.id
  end

  context "#cross_review_replies" do
    test "only returns replies to threads of other reviews" do
      review_one = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      comment = create(:pull_request_review_comment,
        pull_request: @pull,
        pull_request_review: review_one,
        user: @ari,
        body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      review_one.comment!

      review_two = @pull.reviews.create!(user: @bwalsh, head_sha: @pull.head_sha)
      reply = create(:pull_request_review_comment,
        pull_request_review_thread: comment.pull_request_review_thread,
        body: "hey",
        user: @bwalsh,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        pull_request: @pull,
        pull_request_review: review_two,
      )
      review_two.comment!

      assert_empty review_one.review_comments.cross_review_replies
      assert_equal [reply], review_two.review_comments.cross_review_replies.to_a
    end
  end

  test "creating simple review comment" do
    refute @issue.subscribed?(@ari)

    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_predicate comment, :valid?, comment.errors.full_messages.join("\n")

    status = @issue.subscription_status(@ari).value
    assert_predicate status, :subscribed?
    assert_equal "comment", status.reason
  end

  test "gets created with a new review thread" do
    comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
    )

    assert comment.pull_request_review_thread
    comment.reload
    assert comment.pull_request_review_thread

    assert_equal comment.pull_request_id, comment.pull_request_review_thread.pull_request_id
  end

  test "does not get created with a new review thread if the comment is a reply" do
    thread = @pull.review_threads.create!(
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
    )
    comment = create(:pull_request_review_comment,
      pull_request_review_thread: thread,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
    )

    reply = thread.build_reply(
      user: @ari,
      body: "hiya",
    )
    reply.save!

    assert_equal comment.pull_request_review_thread, reply.pull_request_review_thread
    comment.reload
    assert_equal comment.pull_request_review_thread, reply.pull_request_review_thread
  end

  test "subscribes mentioned users to an issue opened by a ghost user" do
    assert_performed_with(job: SubscribeAndNotifyJob) do
      ghost = User.create_ghost
      review = create(:pull_request_review, user: ghost, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: ghost,
        pull_request_review: review,
        body: "Hey @ari lookit this",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )

      assert comment.pull_request_review.comment!

      assert @issue.subscribed?(@ari)
    end
  end

  test "refutes PRRC on locked repo not within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    comment = build(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    refute_predicate comment, :valid?
    assert_includes_match /has been locked for migration/,
      comment.errors.full_messages
  end

  test "accepts PRRC on locked repo within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    GitHub.stubs(:importing?).returns(true)
    comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    assert_predicate comment, :valid?
  end

  test "doesn't allow a repo to be archived" do
    Repository.any_instance.stubs(:archived?).returns(true)
    comment = build(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    refute_predicate comment, :valid?
    assert_includes_match /was archived so is read-only/, comment.errors[:base]
  end

  unless GitHub.enterprise?
    test "fails validation if user is comment blocked" do
      User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
      User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
      comment_ban_user = create(:user)
      ex = assert_raises(ActiveRecord::RecordInvalid) do
        create(:pull_request_review_comment, pull_request: @pull, user: comment_ban_user)
      end
      assert_includes ex.message, "suspended for 1 day"
    end

    context "when interaction limits are enabled" do
      test "fails validation for comment by non-collab" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        ex = assert_raises(ActiveRecord::RecordInvalid) do
          comment = create(:pull_request_review_comment, pull_request: @pull, user: @author)
        end
        assert_equal "Validation failed: could not be created. Interactions on this repository have been restricted to collaborators only.",
          ex.message
      end

      test "passes validation for comment by collaborator" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari)
      end

      test "fails validation when non-collab edits comment" do
        comment = create(:pull_request_review_comment, pull_request: @pull, user: @author)
        comment.submit!
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        refute comment.update_body("hello!", @author)

        assert_includes comment.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end

      test "passes validation when collaborator edits comment" do
        comment = create(:pull_request_review_comment, pull_request: @pull, user: @author)
        comment.submit!
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        assert comment.update_body("hello!", @ari)
        assert_empty comment.errors[:base]
      end
    end
  end

  context "restricted by repository comment checks" do
    context "sock puppet ban" do
      test "denies a 0-day account" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:sockpuppet_disallowed, @ari)

        ex = assert_raises(ActiveRecord::RecordInvalid) do
          create(:pull_request_review_comment, pull_request: @pull, user: @author)
        end
        assert_includes ex.message, "new users"
      end

      test "allows a 3 day old account" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:sockpuppet_disallowed, @ari)

        old_user = create(:user, created_at: 3.days.ago)
        comment = create(:pull_request_review_comment, pull_request: @pull, user: old_user)
        assert comment.valid?
      end
    end

    context "prior contributor" do
      test "denies a non-contributor" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:contributors_only, @ari)

        ex = assert_raises(ActiveRecord::RecordInvalid) do
          create(:pull_request_review_comment, pull_request: @pull, user: @author)
        end
        assert_includes ex.message, "prior contributors only"
      end

      test "allows a prior contributor" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:contributors_only, @ari)

        contributor = create(:user)
        create(:commit_contribution, :with_summaries, repository: @source, user: contributor)

        comment = create(:pull_request_review_comment, pull_request: @pull, user: contributor)
        assert comment.valid?
      end
    end

    context "collaborator" do
      test "denies a non-collaborator" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        ex = assert_raises(ActiveRecord::RecordInvalid) do
          create(:pull_request_review_comment, pull_request: @pull, user: @author)
        end
        assert_includes ex.message, "collaborators only"
      end

      test "allows a collaborator" do
        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @ari)

        collaborator = create(:user)
        @source.add_member(collaborator)

        comment = create(:pull_request_review_comment, pull_request: @pull, user: collaborator)
        assert comment.valid?
      end
    end
  end unless GitHub.enterprise?

  if GitHub.email_verification_enabled?
    test "validating user has verified email to create comment" do
      @ari.stubs(:content_creation_requires_email_verification?).returns(true)
      comment =
        build(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )

      refute_predicate comment, :valid?
      assert comment.errors.present?
      assert_includes_match /email address must be verified/, comment.errors[:base]
    end

    test "users with verified emails can edit unverified users' comments" do
      comment =
        build(:pull_request_review_comment, pull_request: @pull,
          user: @ari,
          body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
        )
      @ari.stubs(:content_creation_requires_email_verification?).returns(true)
      comment.stubs(:modifying_user).returns(@bwalsh)

      assert_predicate comment, :valid?
    end
  end

  test "#message_id includes correct hostname" do
    comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    assert_match /\A\<.*\@github\.com\>\z/, comment.message_id
  end

  test "instruments a pull_request_review_comment.create event" do
    events = subscribe "pull_request_review_comment.create"
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
    )
    expected_payload = {
      comment_id: review_comment.id,
      spammy: review_comment.spammy?,
      submitted: review_comment.submitted?,
      pull_request: review_comment.pull_request.id,
      repo: @source.name_with_display_owner
    }

    assert event = events.pop, "expected an create event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  context "audit logging" do
    test "create is included in audit log" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review_comment.create") do
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari,
          body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
        )
      end
      assert_subset_hash({ pull_request: @pull.id, body: "hiya" }, events.first)
    end

    test "update is included in audit log" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari,
        body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review_comment.update") do
        comment.update!(body: "foo")
      end
      assert_subset_hash({ pull_request: @pull.id, changes: { body: "foo", old_body: "hiya" } }, events.first)
    end

    test "delete is included in audit log" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari,
        body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review_comment.delete") do
        comment.destroy
      end
      assert_subset_hash({ pull_request: @pull.id }, events.first)
    end
  end

  context "Publish to Hydro", skip_enterprise: true do
    test "instruments pull_request_review_comment.create hydro event" do
      Timecop.freeze(Time.now) do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @ari
        comment = create :pull_request_review_comment, pull_request: pull, user: @ari, pull_request_review: review

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published({
            request_context: nil,
            actor: Hydro::EntitySerializer.user(@ari),
            repository: Hydro::EntitySerializer.repository(repo),
            repository_owner: Hydro::EntitySerializer.user(repo.owner),
            pull_request: Hydro::EntitySerializer.pull_request(pull),
            pull_request_review: Hydro::EntitySerializer.pull_request_review(comment.pull_request_review),
            pull_request_review_comment: Hydro::EntitySerializer.pull_request_review_comment(comment),
            issue: Hydro::EntitySerializer.issue(comment.issue),
            specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
            pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(comment.pull_request_review_thread),
          }, schema: "github.v1.PullRequestReviewCommentCreate")
        end
      end
    end

    test "PullRequestReviewComment create publishes github.platform_health.v1.UserGeneratedContent" do
      Timecop.freeze(Time.now) do
        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @ari
        reset_hydro
        comment = create :pull_request_review_comment, pull_request: pull, user: @ari, pull_request_review: review

        message = {
          request_context: nil,
          spamurai_form_signals: nil,
          action_type: :CREATE,
          content_type: :PULL_REQUEST_REVIEW_COMMENT,
          actor: Hydro::EntitySerializer.user(@ari),
          original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.PullRequestReviewCommentCreate"),
          content_database_id: comment.id,
          content_global_relay_id: comment.global_relay_id,
          content_created_at: comment.created_at,
          content_updated_at: comment.updated_at,
          content: Hydro::EntitySerializer.specimen_data(comment.body),
          parent_content_author: Hydro::EntitySerializer.user(pull.user),
          parent_content_database_id: pull.id,
          parent_content_global_relay_id: pull.global_relay_id,
          parent_content_created_at: pull.created_at,
          parent_content_updated_at: pull.updated_at,
          owner: Hydro::EntitySerializer.user(repo.owner),
          repository: Hydro::EntitySerializer.repository(repo),
          content_visibility: :PUBLIC,
          content_url: Hydro::EntitySerializer.url_for_model(comment),
        }

        with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
          assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
        end
      end
    end

    test "instruments pull_request_review_comment.update hydro event" do
      Timecop.freeze(Time.now) do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @ari
        comment = create :pull_request_review_comment, pull_request: pull, user: @ari, pull_request_review: review

        comment.update!(body: "updated comment")

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@ari),
            repository: Hydro::EntitySerializer.repository(repo),
            repository_owner: Hydro::EntitySerializer.user(repo.owner),
            pull_request: Hydro::EntitySerializer.pull_request(pull),
            pull_request_review: Hydro::EntitySerializer.pull_request_review(review),
            pull_request_review_comment: Hydro::EntitySerializer.pull_request_review_comment(comment),
            specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
            issue: Hydro::EntitySerializer.issue(pull.issue),
            feature_flags: []
          }, schema: "github.v1.PullRequestReviewCommentUpdate")
        end
      end
    end

    test "PullRequestReviewComment update publishes github.platform_health.v1.UserGeneratedContent" do
      Timecop.freeze(Time.now) do
        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @ari
        comment = create :pull_request_review_comment, pull_request: pull, user: @ari, pull_request_review: review
        reset_hydro
        comment.update!(body: "updated comment")

        message = {
          request_context: nil,
          spamurai_form_signals: nil,
          action_type: :UPDATE,
          content_type: :PULL_REQUEST_REVIEW_COMMENT,
          actor: Hydro::EntitySerializer.user(@ari),
          original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.PullRequestReviewCommentUpdate"),
          content_database_id: comment.id,
          content_global_relay_id: comment.global_relay_id,
          content_created_at: comment.created_at,
          content_updated_at: comment.updated_at,
          content: Hydro::EntitySerializer.specimen_data(comment.body),
          parent_content_author: Hydro::EntitySerializer.user(pull.user),
          parent_content_database_id: pull.id,
          parent_content_global_relay_id: pull.global_relay_id,
          parent_content_created_at: pull.created_at,
          parent_content_updated_at: pull.updated_at,
          owner: Hydro::EntitySerializer.user(repo.owner),
          repository: Hydro::EntitySerializer.repository(repo),
          content_visibility: :PUBLIC,
          content_url: Hydro::EntitySerializer.url_for_model(comment),
        }

        with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
          assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
        end
      end
    end

    test "instruments pull_request_review_comment.delete hydro event" do
      Timecop.freeze(Time.now) do
        repo = create(:repository, from_example: :pull_request_fork)
        pull = create :pull_request, repository: repo
        review = create :pull_request_review, pull_request: pull, user: @ari
        comment = create :pull_request_review_comment, pull_request: pull, user: @ari, pull_request_review: review

        comment.destroy!

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@ari),
          repository: Hydro::EntitySerializer.repository(repo),
          pull_request: Hydro::EntitySerializer.pull_request(pull),
          pull_request_review: Hydro::EntitySerializer.pull_request_review(comment.pull_request_review),
          pull_request_review_comment: Hydro::EntitySerializer.pull_request_review_comment(comment),
          pull_request_review_thread: Hydro::EntitySerializer.pull_request_review_thread(comment.pull_request_review_thread),
        }, schema: "github.v1.PullRequestReviewCommentDelete")
      end
    end
  end

  test "instruments a pull_request_review_comment.validation_failed event" do
    events = subscribe "pull_request_review_comment.validation_failed"

    review = @pull.pending_review_for(
      user: @ari,
      head_sha: @pull.head_sha,
    )
    thread = review.build_thread
    invalid_comment = thread.build_first_comment(
      user: @ari,
      body: "hiya",
      diff: @pull.pull_comparison.diffs,
      path: "not-a-real-file.txt",
      line: 28,
      side: :right,
    )

    refute invalid_comment.save

    expected_payload = {
      comment_id: nil,
      spammy: invalid_comment.spammy?,
      submitted: invalid_comment.submitted?,
      pull_request: invalid_comment.pull_request.id,
    }

    assert event = events.pop, "expected an create event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  test "instruments a pull_request_review_comment.submission event" do
    events = subscribe "pull_request_review_comment.submission"

    review = @pull.pending_review_for(
      user: @ari,
      head_sha: @pull.head_sha,
    )
    thread = review.build_thread
    review_comment = thread.build_first_comment(
      user: @ari,
      body: "hiya",
      diff: @pull.pull_comparison.diffs,
      path: "aquaman.txt",
      line: 28,
      side: :right,
    )

    assert thread.save
    assert review.comment!
    review_comment.reload

    expected_payload = {
      comment_id: review_comment.id,
      spammy: review_comment.spammy?,
      submitted: review_comment.submitted?,
      pull_request: review_comment.pull_request.id,
    }

    assert event = events.pop, "expected a submission event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  test "instruments a pull_request_review_comment.update event" do
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari,
      body: "Old Body",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
    )
    review_comment.submit!

    events = subscribe "pull_request_review_comment.update"
    review_comment.update_body("New Body", @bwalsh)
    expected_payload = {
      comment_id: review_comment.id,
      spammy: review_comment.spammy?,
      submitted: review_comment.submitted?,
      pull_request: review_comment.pull_request.id,
      repo: @source.name_with_display_owner,
      changes: { old_body: "Old Body", body: "New Body" },
      actor: @bwalsh.login,
      actor_id: @bwalsh.id,
    }

    assert event = events.pop, "expected an update event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  test "instruments a pull_request_review_comment.update with only body when pending" do
    GitHub.context.push(actor_id: @bwalsh.id)
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "Old Body",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )

    events = subscribe "pull_request_review_comment.update"
    review_comment.update_body("New Body", @bwalsh)
    expected_payload = {
      spammy: review_comment.spammy?,
      submitted: review_comment.submitted?,
      pull_request: review_comment.pull_request.id,
      changes: { old_body: "Old Body", body: "New Body" },
      actor: @bwalsh.login,
      actor_id: @bwalsh.id,
      comment_id: review_comment.id,
    }

    assert event = events.pop, "expected an update event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  test "does not instrument a pull_request_review_comment.update when a comment with Japanese characters is submitted" do
    GitHub.context.push(actor_id: @bwalsh.id)
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "レビューコメント - 日本語",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )

    events = subscribe "pull_request_review_comment.update"
    comment = PullRequestReviewComment.find(review_comment.id)
    comment.submit!

    assert_nil events.pop
  end

  test "instruments a pull_request_review_comment.delete event" do
    events = subscribe "pull_request_review_comment.delete"
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    expected_payload = {
      comment_id: review_comment.id,
      spammy: review_comment.spammy?,
      submitted: review_comment.submitted?,
      pull_request: review_comment.pull_request.id,
      repo: review_comment.repository.nwo,
      repo_id: review_comment.repository_id,
      body: review_comment.body,
      author: review_comment.user.login,
      author_id: review_comment.user.id,
      actor: @bwalsh.login,
      actor_id: @bwalsh.id,
    }

    GitHub.context.push(actor_id: @bwalsh.id)
    review_comment = PullRequestReviewComment.find_by(id: review_comment.id)

    review_comment&.destroy

    assert event = events.pop, "expected an instrumentation event to be triggered"
    assert_operator event.payload, :>=, expected_payload
  end

  test "can destroy a review comment after the pull request and repo have been destroyed and not check for spam" do
    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26
    )
    @pull.repository.destroy
    @pull.delete

    PullRequestReviewComment.any_instance.expects(:enqueue_check_for_spam).never

    review_comment.reload
    review_comment.destroy
  end

  test "can destroy a review comment after the pull request and repo and review have been destroyed" do
    review = @pull.reviews.create!(
      user: @ari,
      head_sha: @pull.head_sha,
    )

    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      pull_request_review_id: review.id
    )
    @pull.repository.destroy
    review.delete
    @pull.delete

    c_id = review_comment.id
    review_comment.reload
    assert PullRequestReviewComment.find_by(id: c_id), "Sanity: The issue comment should exist"
    review_comment.destroy
    refute PullRequestReviewComment.find_by(id: c_id), "The review comment should have been deleted, check the destructor chain"
  end

  test "can reparent its replies if its destroyed" do
    review_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 18)

    review_comment_new_parent = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      reply_to_id: review_comment.id)

    review_comment_reply = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      reply_to_id: review_comment.id)

    assert review_comment.destroy, "Review comment is destroyed"

    assert_equal review_comment_new_parent.id, review_comment_reply.reload.reply_to_id,
      "Replies should be reparented to the first reply"
    assert_nil review_comment_new_parent.reload.reply_to_id, "New parent reply_to_id should be nil"
  end

  test "doesn't reparent anything if deleting a reply" do
    review_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26)

    review_comment_reply = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @ari,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      reply_to_id: review_comment.id)

    review_comment_reply.expects(:reparent_replies).never

    assert review_comment_reply.reply?, "Review comment is a reply"
    assert review_comment_reply.destroy, "Review comment is destroyed"
  end

  context "PullRequestReviewCommentEvent" do
    test "is only triggered once on submit, along with the PullRequestReview event" do
      T.unsafe(GitHub).reset_stratocaster

      review = @pull.pending_review_for(
        user: @ari,
        head_sha: @pull.head_sha,
      )
      thread = review.build_thread
      comment = thread.build_first_comment(
        user: @ari,
        body: "hiya",
        diff: @pull.pull_comparison.diffs,
        path: "aquaman.txt",
        line: 28,
        side: :right,
      )

      thread.save

      perform_enqueued_jobs(only: [ProcessEventJob]) do
        review.comment!
        assert_predicate comment.reload, :submitted?
      end

      events = GitHub.stratocaster_store.all

      event = events.last
      assert_equal 2, events.size
      assert_equal "PullRequestReviewCommentEvent", event.event_type
    end

    test "is triggered and sent to all watchers if the comment is not spammy" do
      @bwalsh.watch_repo @source
      assert_equal 3, (@source.watchers + @ari.followers - [@ari]).uniq.size
      T.unsafe(GitHub).reset_stratocaster

      review = @pull.pending_review_for(
        user: @ari,
        head_sha: @pull.head_sha,
      )
      thread = review.build_thread
      comment = thread.build_first_comment(
        user: @ari,
        body: "hiya",
        diff: @pull.pull_comparison.diffs,
        path: "aquaman.txt",
        line: 28,
        side: :right,
      )

      thread.save!

      perform_enqueued_jobs(only: [ProcessEventJob]) { review.comment! }

      event = GitHub.stratocaster_store.last
      targets = Stratocaster.attributes_class_for(event.event_type).from_event(event).targets
      assert_equal "PullRequestReviewCommentEvent", event.event_type
      assert_equal 3, targets.size
    end

    test "is NOT triggered if the comment is from a spammy user" do
      T.unsafe(GitHub).reset_stratocaster

      only = [AddToSearchIndexJob, NotifySubscriptionStatusChangeJob]
      perform_enqueued_jobs(only: only) do
        create(:pull_request_review_comment, pull_request: @pull,
          user: @spammer, body: "free vodka",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )
      end

      refute event = GitHub.stratocaster_store.last, "expected no Stratocaster events to be triggered"
    end
  end

  context "reply validation" do
    test "valid if thread's pending review and comment have the same author" do
      review = @pull.pending_review_for(user: @ari)

      thread = review.build_thread
      thread.build_first_comment(
        user: @ari,
        body: "good code!",
        path: "aquaman.txt",
        line: 5,
      ).save!

      comment = thread.build_reply(
        pull_request_review: review,
        user: @ari,
        body: "good code!",
      )

      assert_predicate comment, :valid?
    end

    test "invalid if thread's pending review and comment do not have the same author" do
      review = @pull.pending_review_for(user: @ari)

      thread = review.build_thread
      thread.build_first_comment(
        user: @ari,
        body: "good code!",
        path: "aquaman.txt",
        line: 5,
      ).save!

      comment = thread.build_reply(
        pull_request_review: review,
        user: create(:user),
        body: "good code!",
      )

      refute_predicate comment, :valid?
      assert_includes comment.errors[:pull_request_review_thread_id].first, "must have review with same author as comment"
    end

    test "valid if thread is published" do
      review = @pull.pending_review_for(user: @ari)

      thread = review.build_thread
      thread.build_first_comment(
        user: @ari,
        body: "good code!",
        path: "aquaman.txt",
        line: 5,
      ).save!
      review.comment!

      review = @pull.pending_review_for(user: create(:user))
      comment = thread.build_reply(
        pull_request_review: review,
        user: review.user,
        body: "good code!",
      )

      assert_predicate comment, :valid?
    end

    test "invalid if thread is not published" do
      review = @pull.pending_review_for(user: @ari)

      thread = review.build_thread
      thread.build_first_comment(
        user: @ari,
        body: "good code!",
        path: "aquaman.txt",
        line: 5,
      ).save!

      review = @pull.pending_review_for(user: create(:user))
      comment = thread.build_reply(
        pull_request_review: review,
        user: review.user,
        body: "good code!",
      )

      refute_predicate comment, :valid?
      assert_includes comment.errors[:pull_request_review_thread_id].first, "must be published"
    end
  end

  test "fails validation with no review thread" do
    comment = @pull.review_comments.build
    refute_predicate comment, :valid?
    assert_equal ["can't be blank"], comment.errors[:pull_request_review_thread]
  end

  context "code scanning review comment" do
    test "fails validation when updating code scanning review comments" do
      thread = code_scanning_thread_with_one_comment
      comment = thread.comments.first
      comment.update_body("new body", @ari)

      refute_predicate comment, :valid?
      assert_equal ["is not editable"], comment.errors[:body]
    end

    test "does not fail validation when submitting code scanning review (with a comment containing No-Break Space)" do
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = @code_scanning_app.bot
      end

      thread = review.build_thread
      thread.build_first_comment(
        user: @ari,
        body: "Test Message with\u{00a0}No-Break Space!",
        path: "aquaman.txt",
        line: 5,
      ).save!

      assert_nothing_raised do
        review.comment!
      end
    end

    test "code scanning review comments cannot be directly deleted" do
      thread = code_scanning_thread_with_one_comment
      comment = thread.comments.first

      assert_equal false, comment.destroy
      assert_equal ["cannot be deleted"], comment.errors[:base]
      assert_equal false, comment.destroyed?
    end

    # Without this, we end up with orphaned comments hanging around in the DB
    # and with error noise.
    test "code scanning review comments can be deleted if the whole PR is deleted" do
      thread = code_scanning_thread_with_one_comment
      comment_id = thread.comments.first.id

      # The check that a comment is a code scanning review comment looks up the corresponding
      # review entity, so if that's already been deleted the check has to assume that the
      # comment doesn't relate to a code scanning review.
      #
      # To test this thoroughly, therefore, we have to ensure that the DestroyDependentRecordsJob
      # which tries to delete the comment runs _before_ the one which deletes the associated
      # review. Otherwise we're not testing the logic properly.
      #
      # This situation can arise in production because Pull Requests contain associations with both
      # their reviews and their comments, so DestroyDependentRecordsJob will be created for both and
      # there's no guarantee which will be picked up first.
      #
      # To do this, we create a Proc rather than just passing a model name to `only`. It's enough
      # in fact to only run the deletion job on the review comment type.

      dependent_records_job_for_comments = proc do |job|
        job.class.name == "DestroyDependentRecordsJob" &&
          job.arguments[2] == :review_comments
      end

      perform_enqueued_jobs(only: dependent_records_job_for_comments) do
        @pull.destroy
        assert_equal true, @pull.destroyed?, "PR was not deleted"
        assert_equal false, PullRequestReviewComment.exists?(comment_id), "Comment was not deleted"
      end
    end

    # Single message threads from code scanning aren't conversations and so can't be considered resolved.
    test "unresolve code scanning review thread when deleting the last remaining reply" do
      thread = code_scanning_thread_with_one_comment

      thread.build_reply(
        pull_request_review: nil,
        user: @ari,
        body: "even better code!"
      ).save!

      thread.resolve(resolver: @ari)

      thread.comments.last.destroy
      assert_equal false, thread.resolved?
    end
  end

  test "only allows writers to comment when locked" do
    issue  = @pull.issue
    repo   = issue.repository
    owner  = repo.owner
    collab = create(:user)
    user   = create(:user)
    staff  = create(:staff_admin_user)

    issue.lock(staff)
    assert_predicate issue, :locked?

    repo.add_member(collab)

    comment =
      build(:pull_request_review_comment, pull_request: @pull,
        user: owner, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_predicate comment, :valid?, comment.errors.full_messages.join("\n")

    comment =
      build(:pull_request_review_comment, pull_request: @pull,
        user: collab, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_predicate comment, :valid?, comment.errors.full_messages.join("\n")

    comment =
      build(:pull_request_review_comment, pull_request: @pull,
        user: user, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    refute_predicate comment, :valid?, comment.errors.full_messages.join("\n")
  end

  if GitHub.prevent_mention_spam?
    test "limits mentioned users to #{mention_limit}" do
      body = @users[0, mention_limit + 1].map { |u| "@#{u}" }.join(", ")
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: body,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )
      assert_predicate comment, :valid?
      assert_equal mention_limit, comment.mentioned_users.length
    end
  else
    test "does not limit mentioned users" do
      body = @users[0, mention_limit + 1].map { |u| "@#{u}" }.join(", ")
      comment =
        create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: body,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
        )
      assert_predicate comment, :valid?
      assert_equal mention_limit + 1, comment.mentioned_users.length
    end
  end

  test "body allows 4-byte unicode characters" do
    content = "\xF0\x9F\x8D\xB7wine"
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: content,
      commit_id: @pull.head_sha,
      path: "aquaman.txt", original_position: 26)
    assert_predicate comment, :valid?
    refute comment.errors[:body].present?
  end

  test "scrubs and stores invalid unicode" do
    content = "\xE5blah" # this is invalid because it is a part of a multibyte unicode sequence
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: content,
      commit_id: @pull.head_sha,
      path: "aquaman.txt", original_position: 26)
    assert_predicate comment, :valid?, "comment should valid"
    assert_equal "�blah", comment.body # converts to the scrubbed characters on read
  end

  test "body must be tagged as UTF-8" do
    content = "a"
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: content,
      commit_id: @pull.head_sha,
      path: "aquaman.txt", original_position: 26)
    assert_equal Encoding::UTF_8, comment.body.encoding
  end

  test "diff_hunk must be tagged as UTF-8" do
    content = "a"
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: content,
      commit_id: @pull.head_sha,
      path: "aquaman.txt", original_position: 26)
    assert_equal Encoding::UTF_8, comment.diff_hunk.encoding
  end

  test "diff_hunk is truncated at MYSQL_UNICODE_BLOB_LIMIT" do
    Object.stub_const(:MYSQL_UNICODE_BLOB_LIMIT, 10) do
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: "a",
        commit_id: @pull.head_sha,
        path: "aquaman.txt", original_position: 26)
      assert_equal MYSQL_UNICODE_BLOB_LIMIT, comment.diff_hunk.bytesize
    end
  end

  test "path must be tagged as UTF-8" do
    content = "a"
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: content,
      commit_id: @pull.head_sha,
      path: "aquaman.txt", original_position: 26)
    assert_equal Encoding::UTF_8, comment.path.encoding
  end

  context "async_body_context" do
    context "if comment may contain a suggestion" do
      test "contains line_number key and prefix is case insensitive" do
        comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: "```suggesTION", commit_id: @pull.head_sha, path: "aquaman.txt", original_position: 26, diff_hunk: "+thilksdjflkdsjfs")
        comment.stubs(:async_current_line).returns(Promise.resolve(10))
        context = comment.async_body_context.sync
        assert_includes context.keys, :start_line_number
      end
    end
    context "if comment does not contain a suggestion" do
      test "does not contain line_number key" do
        comment = create(:pull_request_review_comment, pull_request: @pull, user: @ari, body: "no suggestion here!", commit_id: @pull.head_sha, path: "aquaman.txt", original_position: 26, diff_hunk: "+thilksdjflkdsjfs")
        comment.stubs(:async_current_line).returns(Promise.resolve(10))
        context = comment.async_body_context.sync
        refute_includes context.keys, :start_line_number
      end
    end
  end

  test "assigning original fields on create" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_equal comment.commit_id, comment.original_commit_id
    assert_equal comment.position, comment.original_position
  end

  test "extracting the diff hunk" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_equal @expected_diff_hunk.bytes.to_a, comment.diff_hunk.bytes.to_a
    assert_predicate comment, :live?
    refute_predicate comment, :outdated?
  end

  test "adjusting comment position when diff text changes" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )

    commit = @fork.heads.find("topic-moved").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    comment.reload
    assert_equal 37, comment.position

    assert_predicate comment, :live?
    refute_predicate comment, :outdated?
  end

  test "adjusting comment position when diff text changes and comment is dead" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "this should be changed",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19
      )
    assert_equal " Publication history", comment.diff_hunk.split("\n").last

    commit = @fork.heads.find("topic-moved").target

    with_enqueued_pr_sync_jobs do
      @fork.heads.find("topic").update(commit, @fork.owner)
    end

    comment.reload
    assert_nil comment.position

    assert_predicate comment, :outdated?
    refute_predicate comment, :live?
  end

  test "has a safe user" do
    comment = create(:pull_request_review_comment, pull_request: @pull, user: @bwalsh, body: "irrelevant",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 19
    )

    assert_equal @bwalsh, comment.safe_user

    @bwalsh.destroy
    comment.reload

    assert_equal User.ghost, comment.safe_user
  end

  context "#async_minimizable_by?" do
    test "returns whether the given user can minimize the comment" do
      comment_author = create(:user)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: comment_author, body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19
      )
      comment.submit!
      collab = create(:user)
      @source.add_member(collab)

      assert comment.async_minimizable_by?(@source.owner).sync
      assert comment.async_minimizable_by?(collab).sync
      refute comment.async_minimizable_by?(create(:user)).sync
      assert comment.async_minimizable_by?(create(:staff_admin_user)).sync

      org = create(:organization)
      member = create(:user)
      org.add_member(member)
      @pull.repository.owner = org

      assert comment.async_minimizable_by?(create(:staff_admin_user)).sync
      assert comment.async_minimizable_by?(collab).sync
      refute comment.async_minimizable_by?(member).sync
      refute comment.async_minimizable_by?(create(:user)).sync

      org.block(comment_author)

      assert comment.async_minimizable_by?(create(:staff_admin_user)).sync
      assert comment.async_minimizable_by?(collab).sync
      refute comment.async_minimizable_by?(member).sync
      refute comment.async_minimizable_by?(create(:user)).sync
    end

    test "pending comments cannot be minimized" do
      comment_author = create(:user)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: comment_author,
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      assert comment.pending?
      collab = create(:user)
      @source.add_member(collab)

      # nobody can minimize!
      refute comment.async_minimizable_by?(@source.owner).sync
      refute comment.async_minimizable_by?(collab).sync
      refute comment.async_minimizable_by?(comment_author).sync
      refute comment.async_minimizable_by?((create :user)).sync
      refute comment.async_minimizable_by?(create(:staff_admin_user)).sync
      refute comment.async_minimizable_by?(create(:staff_admin_user)).sync
    end

    test "returns true for comment authored by user" do
      user = create(:user)
      @source.add_member(user, action: :read)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: user,
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      comment.submit!
      refute comment.repository.writable_by?(user)
      assert comment.async_minimizable_by?(user).sync
    end

    if GitHub.organization_moderators_enabled?
      test "returns true for organization moderator" do
        org = create(:organization)
        moderator = create(:user)
        org.add_member(moderator)
        @pull.repository.owner = org
        comment_author = create(:user)
        comment = create(:pull_request_review_comment, pull_request: @pull, user: comment_author, body: "irrelevant",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19
        )
        comment.submit!

        org.moderation.add_moderator(moderator, actor: org.admin)
        assert org.moderator?(moderator)
        assert comment.async_minimizable_by?(moderator).sync
      end

      test "returns true for organization moderator in private repo" do
        org = create(:organization)
        moderator = create(:user)
        org.add_member(moderator)
        @pull.repository.update!(owner: org, public: false)
        assert_predicate @pull.repository, :private?
        comment_author = create(:user)
        comment = create(:pull_request_review_comment, pull_request: @pull, user: comment_author, body: "irrelevant",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19
        )
        comment.submit!

        org.moderation.add_moderator(moderator, actor: org.admin)
        assert org.moderator?(moderator)
        refute comment.async_minimizable_by?(moderator).sync
      end
    end

    test "returns false for user without write access if minimizing other users comment" do
      user = create(:user)
      @source.add_member(user, action: :read)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: create(:user),
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      comment.submit!
      refute comment.async_minimizable_by?(user).sync
    end

    unless GitHub.enterprise?
      test "returns false for the Actions App on a public repo when it does not have permission" do
        random_repo = create(:public_repository, name: "random-repo")

        comment_repo = create(:public_repository, name: "comment-repo", from_example: :review_comment_source)
        issue = create(:issue, user: @bwalsh, repository: comment_repo)
        comment_fork = create(:fork_repository, forker: @bwalsh, fork_repo: comment_repo, from_example: :review_comment_fork)

        pull = create(
          :pull_request,
          repository: comment_repo,
          base_repository: comment_repo,
          base_user: comment_repo.owner,
          base_ref: "master",
          head_repository: comment_fork,
          head_user: comment_fork.owner,
          head_ref: "topic",
          issue: issue,
          user: @bwalsh,
        )

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "pull_requests" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "pull_requests" => :write },
        )

        comment = create(:pull_request_review_comment, pull_request: pull,
          user: scoped_installation.bot,
          body: "irrelevant",
          commit_id: pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
        )
        comment.submit!

        random_installation = make_integration_installation(
          integration: @actions_app,
          repository: random_repo,
          permissions: { "pull_requests" => :write },
        )

        random_scoped_installation = make_scoped_integration_installation(
          parent: random_installation,
          repositories: [random_repo],
          permissions: { "pull_requests" => :write },
        )

        refute comment.async_minimizable_by?(random_scoped_installation.bot).sync
      end

      test "returns true for the Actions App on a public repo when it has permission" do
        comment_repo = create(:public_repository, name: "comment-repo", from_example: :review_comment_source)
        issue = create(:issue, user: @bwalsh, repository: comment_repo)
        comment_fork = create(:fork_repository, forker: @bwalsh, fork_repo: comment_repo, from_example: :review_comment_fork)

        pull = create(
          :pull_request,
          repository: comment_repo,
          base_repository: comment_repo,
          base_user: comment_repo.owner,
          base_ref: "master",
          head_repository: comment_fork,
          head_user: comment_fork.owner,
          head_ref: "topic",
          issue: issue,
          user: @bwalsh,
        )

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "pull_requests" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "pull_requests" => :write },
        )

        comment = create(:pull_request_review_comment, pull_request: pull,
          user: scoped_installation.bot,
          body: "irrelevant",
          commit_id: pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
        )
        comment.submit!

        assert comment.async_minimizable_by?(scoped_installation.bot).sync
      end
    end
  end

  context "#async_viewer_can_update?" do
    test "returns whether the given user can edit the issue" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      refute_predicate @pull.issue, :locked?

      repo   = @pull.repository
      owner  = repo.owner
      collab = create(:user)
      author = comment.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert comment.async_viewer_can_update?(owner).sync
      assert comment.async_viewer_can_update?(collab).sync
      assert comment.async_viewer_can_update?(author).sync
      refute comment.async_viewer_can_update?(staff).sync
      refute comment.async_viewer_can_update?(user).sync
      refute comment.async_viewer_can_update?(nil).sync

      assert @pull.issue.lock(owner)
      assert_predicate @pull.issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      comment = PullRequestReviewComment.find(comment.id)

      assert comment.async_viewer_can_update?(owner).sync
      assert comment.async_viewer_can_update?(collab).sync
      refute comment.async_viewer_can_update?(author).sync
      refute comment.async_viewer_can_update?(staff).sync
      refute comment.async_viewer_can_update?(user).sync
      refute comment.async_viewer_can_update?(nil).sync
    end

    test "with anonymous user and ghost author" do
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @bwalsh, body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19
      )

      comment.user.destroy
      comment.reload

      assert_nil comment.user

      refute comment.async_viewer_can_update?(nil).sync
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      refute_predicate @pull.issue, :locked?

      repo   = @pull.repository
      owner  = repo.owner
      collab = create(:user)
      author = comment.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert_equal [], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync

      # owner has blocked author
      repo.owner.block(author)
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync
      repo.owner.unblock(author)

      # author has blocked collab
      author.block(collab)
      assert_equal [], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync
      author.unblock(collab)

      # collab has blocked author
      collab.block(author)
      assert_equal [], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync
      collab.unblock(author)

      assert @pull.issue.lock(owner)
      assert_predicate @pull.issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      comment = PullRequestReviewComment.find(comment.id)

      assert_equal [], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:locked], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:locked, :insufficient_access], comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:locked, :insufficient_access], comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], comment.async_viewer_cannot_update_reasons(nil).sync
    end

    context "when interaction limits are enabled" do
      test "returns insufficient_access for non-collaborator author" do
        comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @author,
          body: "irrelevant",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
        )
        assert_empty comment.async_viewer_cannot_update_reasons(@author).sync

        interaction = RepositoryInteractionAbility.new(@pull.repository)
        interaction.set_ability(:collaborators_only, @pull.repository.owner)

        assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(@author).sync
      end

      test "returns empty list for maintainer author" do
        comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @author,
          body: "irrelevant",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
        )

        interaction = RepositoryInteractionAbility.new(@pull.repository)
        interaction.set_ability(:collaborators_only, @pull.repository.owner)

        assert_empty comment.async_viewer_cannot_update_reasons(@pull.repository.owner).sync
      end
    end
  end

  context "#async_viewer_can_delete?" do
    test "returns whether the given user can delete the issue" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      refute_predicate @pull.issue, :locked?

      repo   = @pull.repository
      owner  = repo.owner
      collab = create(:user)
      author = comment.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert comment.async_viewer_can_delete?(owner).sync
      assert comment.async_viewer_can_delete?(collab).sync
      assert comment.async_viewer_can_delete?(author).sync
      assert comment.async_viewer_can_delete?(staff).sync
      refute comment.async_viewer_can_delete?(user).sync
      refute comment.async_viewer_can_delete?(nil).sync

      assert @pull.issue.lock(owner)
      assert_predicate @pull.issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      comment = PullRequestReviewComment.find(comment.id)

      assert comment.async_viewer_can_delete?(owner).sync
      assert comment.async_viewer_can_delete?(collab).sync
      refute comment.async_viewer_can_delete?(author).sync
      assert comment.async_viewer_can_delete?(staff).sync
      refute comment.async_viewer_can_delete?(user).sync
      refute comment.async_viewer_can_delete?(nil).sync
    end

    test "can delete ghost user comments" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      repo   = @pull.repository
      owner  = repo.owner
      comment.user.destroy
      comment.reload

      assert comment.async_viewer_can_delete?(owner).sync
    end

    test "owner can delete blocked user comments" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      author = comment.user
      owner = comment.repository.owner
      owner.block(author)
      assert comment.async_viewer_can_delete?(owner).sync
    end

    test "owner can delete blocking user comments" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @users[0],
        body: "irrelevant",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
      )
      author = comment.user
      owner = comment.repository.owner
      author.block(owner)
      assert comment.async_viewer_can_delete?(owner).sync
    end
  end

  test "uses the editing user (not the original user) permissions when editing" do
    repo  = @pull.repository
    owner = repo.owner
    owner.update(plan: "medium")

    user = create(:user, plan: "medium")
    user_private_repo   = create(:private_repository, owner: user)
    owner_private_repo  = create(:private_repository, owner: owner)
    user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
    owner_private_issue = create(:issue, repository: owner_private_repo, user: owner)

    user_private_reference  = [user_private_repo.name_with_owner,  user_private_issue.number].join("#")
    owner_private_reference = [owner_private_repo.name_with_owner, owner_private_issue.number].join("#")

    body  = "Hooray! a comment with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    comment = create(:pull_request_review_comment, pull_request: @pull, user: owner, body: body,
                commit_id: @pull.head_sha,
                path: "aquaman.txt",
                original_position: 19
              )
    comment.submit!

    assert_includes comment.body, "Hooray!"
    refute_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
    assert_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]

    body  = "Hooray! editing the comment with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    comment.update_body(body, user)
    comment = PullRequestReviewComment.find(comment.id)

    assert_includes comment.body, "Hooray!"
    assert_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
    refute_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]
  end

  test "excerpting diff hunk" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "I really like the new SUPERBOY casing. Good job.",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_equal @expected_diff_hunk.bytes.to_a, comment.excerpt.bytes.to_a
  end

  test "changes touch the owning PullRequest" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    # Change updated_at to be old to make the subsequent assertion more clear
    one_week_ago = 1.week.ago
    PullRequest.where(id: @pull.id).update_all(updated_at: one_week_ago)
    Issue.where(id: @pull.issue.id).update_all(updated_at: one_week_ago)

    original_update = comment.pull_request.reload.updated_at

    comment.body = "updated!"
    comment.save!

    assert comment.pull_request.reload.updated_at > original_update
  end

  test "a comment syncs up with the PR when it is created with parameters from an outdated diff" do
    # This tests the case where a user creates a new comment while looking
    # at an outdated version of the diff. If the diff hunk has changed, the
    # position that the comment will be created with will now point at a line
    # other than what the user intended. We have to make sure that the comment
    # recalculates its position if the diff has changed, so that it is displayed
    # at the correct line in the diff.

    original_comment_position = 26
    original_diff_line        = @pull.diffs["aquaman.txt"].lines[original_comment_position]
    original_commit_id        = @pull.head_sha

    original_contents = @fork.blob(original_commit_id, "aquaman.txt").data
    modified_contents = "blah\n#{original_contents}"

    metadata = { message: "an commit", committer: @bwalsh }
    ref      = @fork.heads.find(@pull.head_ref)

    with_enqueued_pr_sync_jobs do
      ref.append_commit(metadata, @bwalsh) do |files|
        files.add("aquaman.txt", modified_contents)
      end
    end

    @pull.reload

    refute_equal original_commit_id, @pull.head_sha

    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @bwalsh,
        body: "YeeAaAaa",
        path: "aquaman.txt",
        original_position: original_comment_position,
        commit_id: original_commit_id,
      )

    # The comment position should have changed, and the new position should
    # point at the same line contents, which just resides at a different
    # position in the diff now.
    refute_equal original_comment_position, comment.position
    assert_equal     original_diff_line, @pull.diffs["aquaman.txt"].lines[comment.position]
  end

  context "recalculating position" do
    test "recalculates positions correctly when diff contains duplicate text" do
      ref = @source.heads.find("master")

      ref.append_commit({ message: "Add fileA", committer: @source.owner }, @source.owner) do |files|
        files.add("fileA", %w[Zero Zero Zero].join("\n"))
      end

      my_branch_ref = @source.heads.create("my-branch", ref.target, @source.user)
      my_branch_ref.append_commit({ message: "Modify fileA", committer: @source.owner }, @source.owner) do |files|
        new_lines = %w[1 2 3 4 5 6]
        files.add("fileA", ["Zero", new_lines, "Zero", new_lines, "Zero"].flatten.join("\n"))
      end

      pull_request = make_pr(@source, @source, branch: "my-branch")

      comment_1 =
        create(:pull_request_review_comment, pull_request: pull_request,
          user: @source.owner,
          body: "YeeAaAaa",
          path: "fileA",
          original_position: 7,
          commit_id: pull_request.head_sha,
        )

      comment_2 =
        create(:pull_request_review_comment, pull_request: pull_request,
          user: @source.owner,
          body: "YeeAaAaa",
          path: "fileA",
          original_position: 14,
          commit_id: pull_request.head_sha,
        )

      assert_equal 7, comment_1.position
      assert_equal 14, comment_2.position
    end

    test "for comment on a skipped entry" do
      commit = @fork.commits.create({ message: "add fileA", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("fileA", (["A"] * 50).join("\n"))
      end

      skipped = @fork.heads.create("skipped", commit, @fork.user)

      pull = make_pr(@source, @fork, branch: "skipped")

      comment =
        create(:pull_request_review_comment, pull_request: pull,
          user: @fork.owner,
          body: "YeeAaAaa",
          path: "fileA",
          original_position: 10,
          commit_id: pull.head_sha,
        )

      assert_equal 9, comment.blob_position

      # watch out, it's a rebase!
      commit = @fork.commits.create({ message: "fileA intro", committer: @fork.owner }, @pull.merge_base) do |files|
        files.add("fileA", ((["welcome to A"] * 10) + (["A"] * 50)).join("\n"))
      end

      # set max diff lines default to an absurdly low number. Because GitHub::Diff#single_entry should be called
      # this will be overridden with the total and everything should be fine when progressive diff loading is
      # enabled.
      GitHub::Diff.max_diff_lines = 5
      with_enqueued_pr_sync_jobs { skipped.update(commit, @fork.owner) }

      comment.reload

      assert_equal 20, comment.position

      # because it was a rebase, the blob position is also updated
      assert_equal 19, comment.blob_position
      assert_equal commit.oid, comment.blob_commit_oid
    end

    test "for a comment beyond the default max_files limit" do
      commit = @fork.commits.create({ message: "add fileZ", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("fileZ", (["Z"] * 50).join("\n"))
      end

      beyond = @fork.heads.create("beyond", commit, @fork.user)

      pull = make_pr(@source, @fork, branch: "beyond")

      comment =
        create(:pull_request_review_comment, pull_request: pull,
          user: @fork.owner,
          body: "YeeAaAaa",
          path: "fileZ",
          original_position: 10,
          commit_id: pull.head_sha,
        )

      assert_equal 9, comment.blob_position

      # watch out, it's a rebase! (needed to force blob positioning)
      commit = @fork.commits.create({ message: "fileZ intro", committer: @fork.owner }, @pull.merge_base) do |files|
        files.add("file111", "this is file 111")
        files.add("file112", "this is file 112")
        files.add("fileZ", ((["welcome to Z"] * 10) + (["Z"] * 50)).join("\n"))
      end

      # set max diff lines default to an absurdly low number. Because GitHub::Diff#single_entry should be called
      # this will be overridden with the total and everything should be fine when progressive diff loading is
      # enabled.
      GitHub::Diff.stub_const(:DEFAULT_MAX_FILES, 1) do
        with_enqueued_pr_sync_jobs { beyond.update(commit, @fork.owner) }

        comment.reload

        assert_equal 20, comment.position

        # because it was a rebase, the blob position is also updated
        assert_equal 19, comment.blob_position
        assert_equal commit.oid, comment.blob_commit_oid
      end
    end
  end

  test "a comment gets outdated when the only change is to add to the end of the line" do
    position = 26
    diff_line = @pull.diffs["aquaman.txt"].lines[position]
    line = diff_line[1..-1]  # discard the diff-marker character ('+', since this line was added)

    commit_id = @pull.head_sha

    original_contents = @fork.blob(commit_id, "aquaman.txt").data
    # add text to the end of the line
    modified_contents = original_contents.sub(Regexp.new(Regexp.escape(line)), "#{line} and more")

    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @bwalsh,
        body: "YeeAaAaa",
        path: "aquaman.txt",
        original_position: position,
        commit_id: commit_id,
      )

    assert_predicate comment, :live?

    metadata = { message: "an commit", committer: @bwalsh }
    ref      = @fork.heads.find(@pull.head_ref)

    with_enqueued_pr_sync_jobs do
      ref.append_commit(metadata, @bwalsh) do |files|
        files.add("aquaman.txt", modified_contents)
      end
    end

    comment.reload

    refute_predicate comment, :live?
  end

  test "it's possible to make a comment in reply to an outdated comment" do
    position = 26
    diff_line = @pull.diffs["aquaman.txt"].lines[position]
    line = diff_line[1..-1]  # discard the diff-marker character ('+', since this line was added)

    commit_id = @pull.head_sha

    original_contents = @fork.blob(commit_id, "aquaman.txt").data
    # add text to the end of the line
    modified_contents = original_contents.sub(Regexp.new(Regexp.escape(line)), "#{line} and more")

    thread = @pull.review_threads.create!(
      path: "aquaman.txt",
      original_position: position,
      commit_id: commit_id,
    )
    comment = create(:pull_request_review_comment,
      pull_request_review_thread: thread,
      pull_request: @pull,
      user: @bwalsh,
      body: "YeeAaAaa",
    )

    assert_predicate comment, :live?

    metadata = { message: "an commit", committer: @bwalsh }
    ref      = @fork.heads.find(@pull.head_ref)

    with_enqueued_pr_sync_jobs do
      ref.append_commit(metadata, @bwalsh) do |files|
        files.add("aquaman.txt", modified_contents)
      end
    end

    comment.reload
    @pull.reload
    thread.reload
    refute_predicate comment, :live?

    original = comment
    comment  = thread.build_reply(
      user: @bwalsh,
      body: "this is a test",
    )

    assert comment.save, comment.errors.full_messages.to_s
    refute_predicate comment, :live?
  end

  test "the final line in the file will get an outdated comment if the change is to add a missing newline" do
    skip "waiting on a better idea, not the highest priority"

    user = @source.owner
    master_oid = @source.refs.read("master").target_oid
    ref = @source.heads.create("no_eol", master_oid, user)

    filename = "whatever.txt"
    metadata = { message: "commit", committer: user }
    contents = %w[there are a bunch of lines here].join("\n")
    ref.append_commit(metadata, user) do |files|
      files.add(filename, contents)
    end

    position = contents.count("\n") + 1

    @issue = create(:issue, user: user, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: user,
        base_ref: "master",
        head_repository: @source,
        head_user: user,
        head_ref: ref.name,
        issue: @issue,
        user: user,
      )
    @issue.pull_request = @pull

    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @bwalsh,
        body: "YeeAaAaa",
        path: filename,
        original_position: position,
        commit_id: ref.target_oid,
      )

    assert_predicate comment, :live?

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      ref.append_commit(metadata, user) do |files|
        files.add(filename, contents + "\n")
      end
    end

    comment.reload

    refute_predicate comment, :live?
  end

  test "the final line in the file will not get an outdated comment if the change does not affect that area" do
    user = @source.owner
    master_oid = @source.refs.read("master").target_oid
    ref = @source.heads.create("no_eol", master_oid, user)

    filename = "whatever.txt"
    metadata = { message: "commit", committer: user }
    contents = %w[there are a bunch of lines here].join("\n") + "\n"
    ref.append_commit(metadata, user) do |files|
      files.add(filename, contents)
    end

    position = contents.count("\n")

    @issue = create(:issue, user: user, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: user,
        base_ref: "master",
        head_repository: @source,
        head_user: user,
        head_ref: ref.name,
        issue: @issue,
        user: user,
      )
    @issue.pull_request = @pull
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @bwalsh,
        body: "YeeAaAaa",
        path: filename,
        original_position: position,
        commit_id: ref.target_oid,
      )
    assert_predicate comment, :live?

    with_enqueued_pr_sync_jobs do
      ref.append_commit(metadata, user) do |files|
        files.add(filename, "blah\n#{contents}")
      end
    end

    comment.reload

    assert_predicate comment, :live?
    assert_equal position + 1, comment.position
  end

  context "blob-positioning attributes" do
    test "are correct for repositioned comments" do
      content = <<~CONTENTS
        this
        is
        a
        new
        file
      CONTENTS

      commit = @fork.commits.create({ message: "add new file", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end

      with_enqueued_pr_sync_jobs { @fork.heads.find(@pull.head_ref).update(commit, @fork.owner) }
      @pull.reload

      review = @pull.reviews.build(user: @source.owner, head_sha: @pull.head_sha)
      thread = review.build_thread
      @comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 4,
        line: 5,
      )
      thread.save
      @comment.submit!

      new_content = <<~CONTENTS
        new
        lines
        before
        this
        is
        a
        new
        file
      CONTENTS

      updated_commit = @fork.commits.create({ message: "add some stuff", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", new_content)
      end
      with_enqueued_pr_sync_jobs { @fork.heads.find(@pull.head_ref).update(updated_commit, @fork.owner) }
      @comment.reload

      assert_equal 4, @comment.original_start_line
      assert_equal 7,  @comment.start_line_number
      assert_equal :right, @comment.start_side
      assert_equal 5, @comment.original_line
      assert_equal 8, @comment.line
      assert_equal :right, @comment.side
    end

    test "are correct for outdated comments where the last line of the diff hunk is the same" do
      content = <<~CONTENTS
        this
        is
        a
        new
        file
      CONTENTS

      commit = @fork.commits.create({ message: "add new file", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", content)
      end

      with_enqueued_pr_sync_jobs { @fork.heads.find(@pull.head_ref).update(commit, @fork.owner) }
      @pull.reload

      review = @pull.reviews.build(user: @source.owner, head_sha: @pull.head_sha)
      thread = review.build_thread
      @comment = thread.build_first_comment(
        body: "multiline comment",
        path: "multiline.txt",
        start_line: 4,
        line: 5,
      )
      thread.save
      @comment.submit!
      new_content = <<~CONTENTS
        changed everything but
        the last line of the
        file
      CONTENTS

      updated_commit = @fork.commits.create({ message: "add some stuff", committer: @fork.owner }, @pull.head_sha) do |files|
        files.add("multiline.txt", new_content)
      end

      with_enqueued_pr_sync_jobs { @fork.heads.find(@pull.head_ref).update(updated_commit, @fork.owner) }
      @comment.reload

      assert_equal 4, @comment.original_start_line
      assert_nil @comment.start_line_number
      assert_equal :right, @comment.start_side
      assert_equal 5, @comment.original_line
      assert_nil @comment.line
      assert_equal :right, @comment.side
    end
  end

  context "submitted_at" do
    test "is created_at for legacy comments" do
      created_at = Time.parse("June 1st, 2016 11:00 AM UTC")
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          created_at: created_at
        )
      assert_equal created_at, comment.submitted_at
    end

    test "is nil if the pull request review has not yet been submitted" do
      created_at = Time.parse("June 1st, 2016 11:00 AM UTC")
      review = @pull.reviews.create!(
        user: @ari,
        head_sha: @pull.head_sha,
      )
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        pull_request_review: review,
        created_at: created_at
      )
      assert_nil comment.submitted_at
    end

    test "is created_at if the pull request review no longer exists" do
      created_at = Time.parse("June 1st, 2016 11:00 AM UTC")
      review = @pull.reviews.create!(
        user: @ari,
        head_sha: @pull.head_sha,
      )
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        pull_request_review: review,
        created_at: created_at
      )

      review.delete
      comment.reload

      assert_equal created_at, comment.submitted_at
    end

    test "is submitted_at from the pull request review" do
      review = @pull.reviews.create!(
        user: @ari,
        head_sha: @pull.head_sha,
      )
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          pull_request_review: review
        )
      review.approve!

      assert_equal review.reload.submitted_at, comment.reload.submitted_at
    end
  end

  test "notifications_thread is the issue" do
    comment =
      create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
    assert_equal @pull.issue, comment.notifications_thread
  end

  context "#generate_issue_event" do
    test "creates an issue event when person deleting is not author" do
      modifying_user = create(:user)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
      comment.stubs(:modifying_user).returns(modifying_user)

      comment.destroy
      issue_event = @pull.issue.events.last

      assert issue_event
      assert_equal issue_event.event, "comment_deleted"
      assert_equal issue_event.actor, modifying_user
      assert_equal issue_event.subject, comment.user
    end

    test "does not create issue event when author deleting own comment" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
      comment.destroy
      assert_equal comment.issue.events.count, 0
    end
  end

  context "#ensure_creator_is_not_blocked" do
    test "disallows pull request review comment when commentor blocked by repo owner" do
      blockee = create(:user)
      comment = build(:pull_request_review_comment, pull_request: @pull,
        user: blockee,
        body: "ugh",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      assert comment.valid?

      @source.owner.block(blockee)
      @pull.reload
      comment = build(:pull_request_review_comment, pull_request: @pull,
        user: blockee,
        body: "ugh",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      refute comment.valid?
      assert_equal "is blocked", comment.errors[:user].first
    end

    test "disallows pull request review comment when commentor blocked by PR owner" do
      blockee = create(:user)
      comment = build(:pull_request_review_comment, pull_request: @pull,
        user: blockee,
        body: "Ugh",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      assert comment.valid?

      @pull.user.block(blockee)
      @pull.reload
      comment = build(:pull_request_review_comment, pull_request: @pull,
        user: blockee,
        body: "Ugh",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      refute comment.valid?
      assert_equal "is blocked", comment.errors[:user].first
    end

    test "allows pull request review comment when commenter is blocked by a PR owner, if commenter has write+ access" do
      blockee = create(:user)
      @pull.repository.add_member(blockee, action: :write)

      @pull.user.block(blockee)
      @pull.reload
      comment = build(:pull_request_review_comment, pull_request: @pull,
        user: blockee,
        body: "Ugh",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
      )
      assert comment.valid?
    end
  end

  context "#selection_contains_deletions?" do
    test "returns true for single line comment on deletion" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        line: 2,
        side: :left,
      )

      assert comment.save, "valid comment could not save!"
      assert comment.selection_contains_deletions?
    end

    test "returns false for single line comment on addition" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        line: 2,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"
      refute comment.selection_contains_deletions?
    end

    test "returns true for multi-line comment with a deletion in the middle" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 17,
        start_side: :right,
        line: 18,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"
      assert comment.selection_contains_deletions?
    end

    test "returns false for multi-line comment with additions and context" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 18,
        start_side: :right,
        line: 19,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"
      refute comment.selection_contains_deletions?
    end
  end

  context "#original_selection" do
    test "returns the diff lines that were commented on" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 5,
        start_side: :right,
        line: 6,
        side: :right,
      )

      assert comment.save, "valid comment could not save!"

      expected_lines = [
        "+1960s superhero-revival period known as the Silver Age of Comic Books, he was a",
        "+founding member of the Justice League of America. In the 1990s Modern Age of",
      ]
      assert_equal expected_lines, comment.original_selection
    end

    test "returns an empty array if the diff hunk is truncated" do
      review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha)
      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "aquaman.txt",
        diff: @pull.historical_comparison.diffs,
        start_line: 2,
        start_side: :right,
        line: 6,
        side: :right,
      )

      Object.stub_const(:MYSQL_UNICODE_BLOB_LIMIT, 10) do
        assert comment.save, "valid comment could not save!"

        comment = PullRequestReviewComment.find(comment.id)
        assert_equal [], comment.pull_request_review_thread&.original_selection
      end
    end
  end

  context "#belongs_to_spammy_content?" do
    test "returns true if pull request is spammy" do
      @pull.user.mark_as_spammy
      @pull.save

      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
      )

      assert comment.belongs_to_spammy_content?
    end

    test "returns true if associated pull request review is spammy" do
      review = @pull.reviews.create!(
          user: @spammer,
          head_sha: @pull.head_sha,
          )
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @ari, body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          pull_request_review: review
      )

      assert comment.belongs_to_spammy_content?
    end
  end unless GitHub.enterprise? # Spammy users don't exist in Enterprise.

  test "legacy comments trigger a SubscribeAndNotifyJob when the body has changed" do
    created_at = Time.parse("June 1st, 2016 11:00 AM UTC")
    comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      created_at: created_at
    )

    assert_enqueued_with job: UpdateSubscriptionsAndNotifyJob do
      comment.update_body("new comment body", comment.user)
    end
  end

  test "non legacy comments trigger a SubscribeAndNotifyJob when the body has changed and the review is submitted" do
    review = create(:pull_request_review, pull_request: @pull, user: @ari)
    body = "comment body"
    review_comment = create(:pull_request_review_comment, pull_request: @pull, pull_request_review: review, user: @ari, body: body)
    review.comment!

    review_comment.reload
    assert_enqueued_with job: UpdateSubscriptionsAndNotifyJob do
      review_comment.update_body("new comment body", review_comment.user)
    end
  end

  test "non legacy comments don't trigger a SubscribeAndNotifyJob when the body has changed and the review is not submitted" do
    review = create(:pull_request_review, pull_request: @pull, user: @ari)
    body = "comment body"
    review_comment = create(:pull_request_review_comment, pull_request: @pull, pull_request_review: review, user: @ari, body: body)

    review_comment.reload
    assert_no_enqueued_jobs only: UpdateSubscriptionsAndNotifyJob do
      review_comment.update_body("new comment body", review_comment.user)
    end
  end

  test "updates subscriptions with new mentions and sends notifications" do
    review_mention_user = create(:user, :verified)
    accidental_review_comment_mention_user = create(:user, :verified)
    updated_review_comment_mention_user = create(:user, :verified)

    enable_notifications_for_user(review_mention_user)
    enable_notifications_for_user(accidental_review_comment_mention_user)
    enable_notifications_for_user(updated_review_comment_mention_user)

    review = @pull.reviews.create!(user: @ari, head_sha: @pull.head_sha, body: "Hey @#{review_mention_user}")
    thread = review.build_thread
    comment = thread.build_first_comment(
      body: "Hey @#{accidental_review_comment_mention_user}",
      path: "aquaman.txt",
      diff: @pull.historical_comparison.diffs,
      line: 6,
      side: :right,
    )
    assert comment.save

    assert_performed_with job: SubscribeAndNotifyJob do
      review.comment!
    end

    assert @pull.notifications_thread.subscribed? review_mention_user
    assert @pull.notifications_thread.subscribed? accidental_review_comment_mention_user
    refute @pull.notifications_thread.subscribed? updated_review_comment_mention_user

    assert_delivered_email_notification(review_mention_user, review, "mention")
    assert_delivered_email_notification(accidental_review_comment_mention_user, review, "mention")
    refute_delivered_any_notifications(updated_review_comment_mention_user)

    subject = review

    # Reload comment or else it won't know that it's been submitted
    comment.reload
    assert_performed_with job: UpdateSubscriptionsAndNotifyJob do
      comment.update_body("Hey @#{updated_review_comment_mention_user}", comment.user)
    end

    assert @pull.notifications_thread.subscribed? review_mention_user
    refute @pull.notifications_thread.subscribed? accidental_review_comment_mention_user
    assert @pull.notifications_thread.subscribed? updated_review_comment_mention_user

    assert_delivered_email_notification(updated_review_comment_mention_user, subject, "mention")
  end

  context "unminimize a comment" do
    test "returns false when pending?" do
      pending_comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
      )

      pending_comment.update(comment_hidden_by: ROLES[:minimized_by_staff])
      refute pending_comment.async_unminimizable_by?(@staff_user).sync
    end

    test "only staff can unminimize staff-minimized comment" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
      )
      comment.submit!

      comment.update(comment_hidden_by: ROLES[:minimized_by_staff])
      refute comment.async_unminimizable_by?(@author).sync
      refute comment.async_unminimizable_by?(@maintainer).sync
      assert comment.async_unminimizable_by?(create(:staff_admin_user)).sync
    end

    test "maintainer & staff can unminimize maintainer-minimized comment" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
      )
      comment.submit!

      comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])
      assert comment.async_unminimizable_by?(@maintainer).sync
      assert comment.async_unminimizable_by?(create(:staff_admin_user)).sync
      refute comment.async_unminimizable_by?(@author).sync
    end

    test "maintainer, staff & the commenting author can unminimize author-minimized comment" do
      comment_author = create(:user)
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: comment_author, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
      )
      comment.submit!

      comment.update(comment_hidden_by: ROLES[:minimized_by_author])
      assert comment.async_unminimizable_by?(@maintainer).sync
      assert comment.async_unminimizable_by?(create(:staff_admin_user)).sync
      refute comment.async_unminimizable_by?(@author).sync
      assert comment.async_unminimizable_by?(comment_author).sync
    end

    test "contributor cannot unminimize maintainer-minimized comment" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26
      )
      comment.submit!

      comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])
      refute comment.async_unminimizable_by?(@author).sync
      assert comment.async_unminimizable_by?(create(:staff_admin_user)).sync
    end

    test "stores the right comment hidden by value" do
      author_minimized_comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 28
      )
      author_minimized_comment.submit!
      author_minimized_comment.set_minimized(@author, "reason", "spam", @author, staff = false)
      maintainer_minimized_comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 29
      )
      maintainer_minimized_comment.submit!
      maintainer_minimized_comment.set_minimized(@maintainer, "reason", "spam", @author, staff = false)
      staff_minimized_comment = create(:pull_request_review_comment, pull_request: @pull,
          user: @maintainer, body: "spam",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 30
      )
      staff_minimized_comment.submit!
      staff_minimized_comment.set_minimized(@staff_user, "reason", "spam", @author, staff = true)


      assert_equal("minimized_by_author", author_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_maintainer", maintainer_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_staff", staff_minimized_comment.comment_hidden_by)
    end
  end

  context "update pull request counters" do
    test "must update the counters when a review comment is submitted" do
      date = Date.new(2016, 2, 3)
      comment1 = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: date
      )
      comment1.submit!
      assert_review_comments 1, @pull

      comment2 = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: date
      )
      comment2.submit!
      assert_review_comments 2, @pull
    end

    test "should update the counter when the body is changed" do
      date = Date.new(2016, 2, 3)
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: date
      )
      comment.submit!
      assert_review_comments 1, @pull

      # forcing the body being nil should decrement the counter
      comment.update_attribute(:body, nil)
      assert_review_comments 0, @pull

      # adding a new body should update the counter
      comment.update_attribute(:body, "hello again")
      assert_review_comments 1, @pull

      # forcing the body being empty should decrement
      comment.update_attribute(:body, "")
      assert_review_comments 0, @pull

      # forcing the body being nil should decrement and avoid negative numbers
      comment.update_attribute(:body, nil)
      assert_review_comments 0, @pull
    end

    test "must update the counters when a review comment is destroyed" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: Date.new(2016, 2, 3)
      )
      comment.submit!
      assert_review_comments 1, @pull

      comment.destroy!
      assert_review_comments 0, @pull
    end

    test "delete a pending review comment should not update the counters" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "hiya",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        created_at: Date.new(2016, 2, 3)
      )
      comment.submit!
      assert_review_comments 1, @pull
      assert_nil @pull.reviews_with_body_count

      review = @pull.reviews.create!(
        user: @ari,
        head_sha: @pull.head_sha
      )

      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "not update",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26,
        pull_request_review_id: review.id
      )
      assert_review_comments 1, @pull
      assert_nil @pull.reviews_with_body_count

      comment.destroy!
      assert_review_comments 1, @pull
      assert_nil @pull.reviews_with_body_count
    end

    test "updating a body should not update the counters" do
      comment = create(:pull_request_review_comment, pull_request: @pull,
        user: @ari, body: "do not update",
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 26
      )
      comment.submit!
      assert_review_comments 1, @pull

      comment.update_attribute(:body, "yeah! updated")
      assert_review_comments 1, @pull

      comment.destroy!
      assert_review_comments 0, @pull
    end
  end

  test "destroying review comment deletes empty review & review thread" do
    review        = create(:pull_request_review, pull_request: @pull, user: @ari, body: nil)
    comment       = create(:pull_request_review_comment, pull_request: @pull, user: @ari, pull_request_review: review)
    review_thread = comment.pull_request_review_thread
    assert review.comment!

    assert comment.reload.destroy

    assert_raises(ActiveRecord::RecordNotFound) { comment.reload }
    assert_raises(ActiveRecord::RecordNotFound) { review.reload }
    assert_raises(ActiveRecord::RecordNotFound) { review_thread.reload }
  end

  test "destroying review comment deletes empty review but not shared review thread" do
    review1               = create(:pull_request_review, pull_request: @pull, user: @ari, body: nil)
    comment1              = create(:pull_request_review_comment, pull_request: @pull, user: @ari, pull_request_review: review1)
    shared_review_thread  = comment1.pull_request_review_thread
    assert review1.comment!

    review2   = create(:pull_request_review, pull_request: @pull, user: @bwalsh, body: nil)
    comment2  = create(:pull_request_review_comment, pull_request: @pull, user: @bwalsh, pull_request_review: review2,
                  reply_to_id: comment1.id, pull_request_review_thread: shared_review_thread)
    assert review2.comment!

    # We don't want to enqueue a job that destroys the review thread association
    assert_no_performed_jobs(only: DestroyDependentRecordsJob) do
      assert comment1.reload.destroy
    end

    assert_raises(ActiveRecord::RecordNotFound) { comment1.reload }
    assert_raises(ActiveRecord::RecordNotFound) { review1.reload }

    assert comment2.reload, "shouldn't have been destroyed"
    assert shared_review_thread.reload, "shouldn't have been destroyed"
  end

  test "deletes review thread even if the review has a body after destoy" do
    review = @pull.reviews.create!(
      user: @ari,
      head_sha: @pull.head_sha,
      body: "heyo"
    )

    review_comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @ari, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      pull_request_review_id: review.id
    )

    assert thread = review_comment.pull_request_review_thread

    review_comment.destroy

    refute PullRequestReviewThread.exists?(thread.id)
  end

  test "callbacks are accounted for in DeletePullRequestReviewCommentOrchestration, CreateReplyPullRequestReviewCommentOrchestration, and CreateNewPullRequestReviewCommentOrchestration" do
    base_message =
"If this change applies to a callback invoked when creating or deleting a
comment, please ensure that it is applied to the orchestrations responsible
for deleting a comment, creating a new comment, or creating a reply"

    expected_callbacks_and_counts = {
        validate: 23,
        validation: 6,
        initialize: 0,
        find: 0,
        touch: 0,
        save: 11,
        create: 8,
        update: 9,
        destroy: 5,
        commit: 16,
        rollback: 0,
        before_commit: 0,
    }

    unless PullRequestReviewComment.__callbacks.keys == expected_callbacks_and_counts.keys
      fail "New callback type introduced on the PullRequestReviewComment model. \n#{base_message}"
    end

    expected_callbacks_and_counts.each do |name, count|
      assert_equal PullRequestReviewComment.send("_#{name}_callbacks".to_sym).count, count, callback_count_message(name, count, PullRequestReviewComment.send("_#{name}_callbacks".to_sym).count, base_message)
    end
  end

  private

  def callback_count_message(callback_type_name, from_count, to_count, base_message)
    "Callback count changed for #{callback_type_name} callbacks on the PullRequestReviewComment model from #{from_count} to #{to_count}. \n#{base_message}"
  end

  def assert_review_comments(value, pull)
    pull.reload
    assert_nil pull.review_comments_with_body_count if value.nil?
    assert_equal value, pull.review_comments_with_body_count unless value.nil?
  end

  def code_scanning_thread_with_one_comment
    review = @pull.build_code_scanning_variant_review do |r|
      r.user = @code_scanning_app.bot
    end

    thread = review.build_thread
    thread.build_first_comment(
      user: @ari,
      body: "good code!",
      path: "aquaman.txt",
      line: 5,
    ).save!
    review.comment!

    thread
  end
end
