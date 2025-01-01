# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitCommentTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  ROLES = GitHub::MinimizeComment::ROLES

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, from_example: :commit_comments)
    @org_owned_repo = create(:repository, owner: @org, from_example: :commit_comments)


    @org_admin = @org.admins.first
    @org_repo = create(:repository, owner: @org, from_example: :commit_comments)

    @team_member = create(:user)
    @team = create(:team, organization: @org)
    @team.add_member(@team_member)

    @team_member_two = create(:user)
    @team_two = create(:team, organization: @org)
    @team_two.add_member(@team_member_two)

    @owner      = @repo.owner
    @owner.watch_repo @repo
    @collab     = create(:user)
    @user2      = create(:user)
    @watcher    = create(:user)
    @rick       = create :user, email: "technoweenie@gmail.com" # author of @commit2
    @spammer    = create :user, spammy: true
    @verified   = create :verified_user
    @org_member = create(:user)
    @org_repo_collab = create(:user)
    @author = create(:user)
    @maintainer = create(:user)
    @mannequin = create(:mannequin)
    @staff_user = create(:staff_admin_user)
    @repo.add_member(@author, action: :read)
    @repo.add_member(@maintainer, action: :write)
    @org.add_member(@org_member)
    @org_owned_repo.add_member(@org_repo_collab)
    @commit     = "3572d83ba062076f6a740379463d0f3f770d7fc5"
    @commit2    = "c3956841a7cb7e8ba4a6fd923568d86958f01573"
    @commit3    = "c3956841a7cb7e8ba4a6fd923568d86958f01574"
    @comment = create :commit_comment, user: @owner, repository: @repo,
                      position: 0, path: "color.js", commit_id: @commit3
    @comment2_1 = create :commit_comment, user: @owner, repository: @repo,
      position: 0, path: "color.js", commit_id: @commit2
    @comment2_2 = create :commit_comment, user: @owner, repository: @repo,
      position: 4, path: "color.js", commit_id: @commit2
    @comment2_3 = create :commit_comment, user: @user2, repository: @repo,
      position: 4, path: "geometry.js", commit_id: @commit2
    @comment2_4 = create :commit_comment, user: @user2, repository: @repo,
      position: nil, path: nil, commit_id: @commit2

    @inline_comment = create :commit_comment, repository: @repo, commit_id: @repo.default_oid, user: @repo.owner
    @commit_comment = create :commit_comment, repository: @repo, commit_id: @repo.default_oid, user: @repo.owner, path: nil, position: nil

    @owner.follow @user2
    @watcher.watch_repo @repo
    @repo.add_member(@collab)
    @collab.watch_repo(@repo)

    @collaborator_repository = create(:repository)
    @contributor_repository = create(:repository)

    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration)
    refute_nil @actions_app
  end

  setup do
    example_repo :commit_comments, @repo
    example_repo :commit_comments, @org_repo
  end

  setup_once { disable_monolith_rate_limiter_redis }
  teardown_once { enable_monolith_rate_limiter_redis }

  def spammy_comment
    "How much do you love http://cialis.com?"
  end

  test "is never pending" do
    refute_predicate CommitComment.new, :pending?
    refute_predicate @comment2_1, :pending?
    refute_predicate @comment2_2, :pending?
  end

  context "mentions" do
    test "queues up when a user is mentioned on create" do
      body = "thoughts @#{@user2}?"

      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create(:commit_comment, user: @owner, repository: @repo, body: body, commit_id: @commit)
        assert comment.subscribed?(@user2)
        assert_equal "mention", comment.subscription_status(@user2).reason
      end
    end

    test "queues up, but doesn't subscribe user, on create if author is spammy" do
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      @owner.update_attribute(:spammy, true)
      body = "thoughts @#{@user2}?"

      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create(:commit_comment, user: @owner, repository: @repo, body: body, commit_id: @commit)
        refute comment.subscribed?(@user2)
      end
    end

    test "queues up when a team is mentioned on create" do
      body = "thoughts @#{@team.combined_slug}?"

      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create(:commit_comment, user: @org_admin, repository: @org_repo, body: body, commit_id: @commit)
        assert comment.subscribed?(@team_member)
        assert_equal "team_mention", comment.subscription_status(@team_member).reason
      end
    end

    test "queues up, but doesn't subscribe team, on create if author is spammy" do
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      @org_admin.update_attribute(:spammy, true)
      body = "thoughts @#{@team.combined_slug}?"

      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create(:commit_comment, user: @org_admin, repository: @org_repo, body: body, commit_id: @commit)
        refute comment.subscribed?(@team_member)
      end
    end

    test "queues up when a user is mentioned on update" do
      body = "thoughts @#{@owner}?"
      new_body = "thoughts @#{@user2}?"

      comment = create(:commit_comment, user: @owner, repository: @repo, body: body, commit_id: @commit)
      assert_enqueued_with(job: UpdateSubscriptionsAndNotifyJob, args: [subject: comment, previous_body: [body, new_body], deliver_notifications: true, spam_check_delay_served: false]) do
        comment.body = new_body
        comment.save
      end
    end

    test "queues up when a team is mentioned on update" do
      body = "thoughts @#{@team.combined_slug}?"
      new_body = "thoughts @#{@team_two.combined_slug}?"

      comment = create(:commit_comment, user: @owner, repository: @repo, body: body, commit_id: @commit)
      assert_enqueued_with(job: UpdateSubscriptionsAndNotifyJob, args: [subject: comment, previous_body: [body, new_body], deliver_notifications: true, spam_check_delay_served: false]) do
        comment.body = new_body
        comment.save
      end
    end
  end

  context "CommitComment" do
    test "does not check for spam when issue is destroyed without a repo" do
      @repo.delete
      @comment2_1.reload

      CommitComment.any_instance.expects(:enqueue_check_for_spam).never
      @comment2_1.destroy
    end

    test "does not check for spam at all when destroyed" do
      CommitComment.any_instance.expects(:enqueue_check_for_spam).never
      @comment2_1.destroy
    end

    test "can find review threads" do
      threads = CommitCommentThread.review_threads(viewer: @owner, commit: @repo.commits.find(@commit2), repository: @repo)
      color_threads = threads.path("color.js")
      assert_equal 3, threads.size # 2 color.js, 1 geometry.js
      assert_equal 2, color_threads.size
      assert_equal @comment2_1, color_threads.position(0).first.comments[0]
      assert_equal @comment2_2, color_threads.position(4).first.comments[0]
    end

    test "finds all comments for a position" do
      commits = CommitComment.find_for_position(0, "color.js",
        @owner, @commit2, @repo)
      assert_equal 1, commits.size
      assert_equal @comment2_1, commits.first
    end

    test "finds all comments for a commit" do
      commits = CommitComment.find_for(@owner, @commit2, @repo)
      assert_equal @comment2_1, commits[0]
      assert_equal @comment2_2, commits[1]
      assert_equal @comment2_3, commits[2]
      assert_equal @comment2_4, commits[3]
      assert_equal 4, commits.size
    end

    test "finds all comments for a commit with a path" do
      commits = CommitComment.find_for(@owner, @commit2, @repo, true)
      assert_equal @comment2_1, commits[0]
      assert_equal @comment2_2, commits[1]
      assert_equal @comment2_3, commits[2]
      assert_equal 3, commits.size
    end

    test "misses return []" do
      assert_equal [], CommitComment.find_for(@owner, "12421515", @repo)

      assert_equal [], CommitComment.find_for_position(10123,
        "color.js", @owner, @commit2, @repo)
    end
  end

  context "An instance of CommitComment" do
    test "is inline? when it has a path" do
      assert @inline_comment.inline?
    end

    test "is not inline? when it has no path" do
      refute @commit_comment.inline?
    end

    test "has r#id prefix fragment for inline comments" do
      assert @inline_comment.full_permalink.end_with? "r#{@inline_comment.id}"
    end

    test "has commitcomment#id prefix fragment for commit comments" do
      assert @commit_comment.full_permalink.end_with? "commitcomment-#{@commit_comment.id}"
    end
  end

  context "Creating a CommitComment" do
    test "instruments a commit_comment.create event" do
      events = subscribe "commit_comment.create"
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js")

      comment.stubs(:modifying_user).returns(@user2)

      expected_payload = {
        spammy: comment.spammy?,
        allowed: false,
        body: comment.body,
        author: @user2.to_s,
        author_id: @user2.id,
        commit_comment_id: comment.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @user2.to_s,
        actor_id: @user2.id,
      }

      assert event = events.pop, "expected an instrumenation event"
      assert_equal expected_payload, event.payload
    end

    test "publishes a CommitCommentCreate hydro event", skip_enterprise: true do
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:commit_comment_scanning_service_flags).returns([])

      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js")

      comment.stubs(:modifying_user).returns(@user2)

      expected_message = {
        actor: Hydro::EntitySerializer.user(@user2),
        actor_is_member: false,
        body: comment.body,
        commit_comment: {
          id: comment.id,
          global_relay_id: comment.global_relay_id,
          oid: comment.commit.oid,
          repository_id: comment.repository_id,
          author_id: comment.user_id,
          created_at: comment.created_at,
          updated_at: comment.updated_at,
        },
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@owner),
        request_context: nil,
        spamurai_form_signals: nil,
        specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
        feature_flags: []
      }

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(expected_message, schema: "github.v1.CommitCommentCreate")
        assert_hydro_messages(count: 1, schema: "github.v1.CommitCommentCreate")
      end
    end

    test "CommitComment create publishes github.platform_health.v1.UserGeneratedContent", skip_enterprise: true do
      reset_hydro
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js")

      comment.stubs(:modifying_user).returns(@user2)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :CREATE,
        content_type: :COMMIT_COMMENT,
        actor: Hydro::EntitySerializer.user(@user2),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.CommitCommentCreate"),
        content_database_id: comment.id,
        content_global_relay_id: comment.global_relay_id,
        content_created_at: comment.created_at,
        content_updated_at: comment.updated_at,
        content: Hydro::EntitySerializer.specimen_data(comment.body),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: Hydro::EntitySerializer.user(@owner),
        repository: Hydro::EntitySerializer.repository(@repo),
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(comment),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "creates events for all watchers" do
      assert_equal 3, (@repo.watchers + @user2.followers).uniq.size
      T.unsafe(GitHub).reset_stratocaster

      perform_enqueued_jobs(only: [ProcessEventJob]) do
        create(:commit_comment, user: @user2, repository: @repo,
          commit_id: @commit2, path: "color.js")
      end
      event = GitHub.stratocaster_store.last
      assert_equal "CommitCommentEvent", event.event_type
    end

    test "subscribes commit author and comment author to the thread" do
      commit = @repo.commits.find(@commit2)
      create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js")

      status = GitHub.newsies.subscription_status(@user2, @repo, commit).value
      assert status.subscribed?
      assert_equal "comment", status.reason

      status = GitHub.newsies.subscription_status(@rick, @repo, commit).value
      assert status.subscribed?
      assert_equal "author", status.reason
    end

    test "body must be tagged as UTF-8" do
      assert_equal Encoding::UTF_8, @comment2_1.body.encoding
    end

    test "path must be tagged as UTF-8" do
      assert_equal Encoding::UTF_8, @comment2_1.path.encoding
    end

    test "body is limited to unicode_blob_limit length" do
      # We want to validate on bytelength and return a human readable error
      # message with a pessimistic character limit for MYSQL_UNICODE_BLOB_LIMIT
      expected_bytes = 262144
      expected_characters = expected_bytes / 4
      content = "a" * expected_bytes
      comment = CommitComment.new(user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: content)
      assert comment.valid?

      comment.body = content + "aa"
      refute comment.valid?
      assert_equal comment.errors[:body][0], "is too long (maximum is #{expected_characters} characters)"
    end

    test "refutes commit comments on locked repo not within migration" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      refute @comment2_1.valid?
      assert_includes_match /has been locked for migration/,
        @comment2_1.errors.full_messages
    end

    test "accepts commit comments on locked repo within migration" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      GitHub.stubs(:importing?).returns(true)
      assert @comment2_1.valid?
    end

    test "refutes commit comments on archived repo" do
      Repository.any_instance.stubs(:archived?).returns(true)
      refute @comment2_1.valid?
      assert_includes_match /Commit has been locked/,
        @comment2_1.errors.full_messages
    end

    test "remains valid when the comment author has lost access to the repository" do
      @repo.toggle_visibility(actor: @repo.owner)
      @comment2_3.stubs(:modifying_user).returns(@repo.owner)

      assert @comment2_3.valid?
    end

    if GitHub.email_verification_enabled?
      test "validates that the user must have a verified email" do
        @user2.stubs(:content_creation_requires_email_verification?).returns(true)
        comment = build(:commit_comment, user: @user2, repository: @repo, commit_id: @commit2, path: "color.js")
        assert @user2.must_verify_email?,
          "Bad assumption: User is not required to verify their email address."
        refute comment.valid?
        assert_includes_match /email address must be verified/,
          comment.errors.full_messages
      end

      test "validates that the modifying user can update even if original user must_verify_email?" do
        comment = create(:commit_comment, user: @user2, repository: @repo, commit_id: @commit2, path: "color.js")
        @user2.stubs(:must_verify_email?).returns(true)
        refute comment.valid?
        comment.stubs(:modifying_user).returns(@collab)
        assert comment.valid?
      end

      test "users with verified emails can comment" do
        @verified.stubs(:content_creation_requires_email_verification?).returns(true)
        comment = build(:commit_comment, user: @verified, repository: @repo, commit_id: @commit2, path: "color.js")
        assert comment.valid?
      end
    end

    test "validates that the repo owner has not blocked the comment author" do
      blocked_user = create(:user)
      @owner.block(blocked_user)
      ex = assert_raises(ActiveRecord::RecordInvalid) do
        create(:commit_comment, user: blocked_user, repository: @repo, commit_id: @commit2)
      end
      assert_equal "Validation failed: User is blocked", ex.message
    end

    test "validates that the commit author has not blocked the comment author" do
      commit_author = @repo.commits.find(@commit2).author
      blocked_user = create(:user)
      commit_author.block(blocked_user)

      ex = assert_raises(ActiveRecord::RecordInvalid) do
        create(:commit_comment, user: blocked_user, repository: @repo, commit_id: @commit2)
      end
      assert_equal "Validation failed: User is blocked", ex.message
    end

    test "clears line/position if path is nil" do
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: nil, line: 0, position: 0)

      assert_nil comment.path
      assert_nil comment.line
      assert_nil comment.position

      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: nil, line: 10, position: 5)

      assert_nil comment.path
      assert_nil comment.line
      assert_nil comment.position
    end

    test "loads commit comment counts for commits in batch" do
      commits = @repo.commits.find([@commit, @commit2])
      CommitComment.attach_counts_to_commits(commits, batch_size: 1)
      assert_equal [0, 4], commits.collect(&:comment_count)
    end
  end

  context "Updating a CommitComment" do
    test "instruments a commit_comment.update event" do
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")

      comment.stubs(:modifying_user).returns(@user2)

      events = subscribe "commit_comment.update"
      comment.update!(body: "New Body")
      expected_payload = {
        spammy: comment.spammy?,
        allowed: false,
        body: comment.body,
        changes: {
          body: comment.body,
          old_body: "Old Body",
        },
        author: @user2.to_s,
        author_id: @user2.id,
        commit_comment_id: comment.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @user2.to_s,
        actor_id: @user2.id,
      }

      assert event = events.pop, "expected an instrumenation event"
      assert_equal expected_payload, event.payload
    end

    test "publishes a CommitCommentUpdate hydro event", skip_enterprise: true do
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:commit_comment_scanning_service_flags).returns([])

      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")

      comment.stubs(:modifying_user).returns(@user2)
      comment.update!(body: "New Body")

      expected_message = {
        actor: Hydro::EntitySerializer.user(@user2),
        actor_is_member: false,
        commit_comment: {
          id: comment.id,
          global_relay_id: comment.global_relay_id,
          oid: comment.commit.oid,
          repository_id: comment.repository_id,
          author_id: comment.user_id,
          created_at: comment.created_at,
          updated_at: comment.updated_at,
        },
        current_body: "New Body",
        previous_body: "Old Body",
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@owner),
        request_context: nil,
        spamurai_form_signals: nil,
        specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
        feature_flags: []
      }

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(expected_message, schema: "github.v1.CommitCommentUpdate")
        assert_hydro_messages(count: 1, schema: "github.v1.CommitCommentUpdate")
      end
    end

    test "CommitComment update publishes github.platform_health.v1.UserGeneratedContent", skip_enterprise: true do
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")
      comment.stubs(:modifying_user).returns(@user2)
      reset_hydro
      comment.update!(body: "New Body")

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :UPDATE,
        content_type: :COMMIT_COMMENT,
        actor: Hydro::EntitySerializer.user(@user2),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.CommitCommentCreate"),
        content_database_id: comment.id,
        content_global_relay_id: comment.global_relay_id,
        content_created_at: comment.created_at,
        content_updated_at: comment.updated_at,
        content: Hydro::EntitySerializer.specimen_data(comment.body),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: Hydro::EntitySerializer.user(@owner),
        repository: Hydro::EntitySerializer.repository(@repo),
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(comment),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reasons that prevent the user from updating the comment" do
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")

      assert_equal [], comment.async_viewer_cannot_update_reasons(@owner).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(@user2).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(@watcher).sync

      @repo.commits.find(@commit2).lock(@owner)

      # Find a new object so that we don't keep any cached ivars around
      comment = CommitComment.find comment.id
      assert_equal [], comment.async_viewer_cannot_update_reasons(@owner).sync
      assert_equal [:locked], comment.async_viewer_cannot_update_reasons(@user2).sync
      assert_equal [:locked, :insufficient_access], comment.async_viewer_cannot_update_reasons(@watcher).sync
    end
  end

  context "#async_minimizable_by?" do
    test "returns whether the given user can minimize the comment" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })
      org_comment = create(:commit_comment, {
        user: @user2,
        repository: @org_owned_repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old body",
      })
      collab = create(:user)
      @repo.add_member(collab)

      assert comment.async_minimizable_by?(create(:staff_admin_user)).sync
      assert comment.async_minimizable_by?(@owner).sync
      assert comment.async_minimizable_by?(collab).sync
      refute comment.async_minimizable_by?(create(:user)).sync

      assert org_comment.async_minimizable_by?(create(:staff_admin_user)).sync
      assert org_comment.async_minimizable_by?(@org_repo_collab).sync
      refute org_comment.async_minimizable_by?(create(:user)).sync
      refute org_comment.async_minimizable_by?(@org_member).sync

      @org.block(@user2)

      assert org_comment.async_minimizable_by?(create(:staff_admin_user)).sync
      assert org_comment.async_minimizable_by?(@org_repo_collab).sync
      refute org_comment.async_minimizable_by?(create(:user)).sync
      refute org_comment.async_minimizable_by?(@org_member).sync
    end

    test "returns true for comment authored by user" do
      collab = create(:user)
      comment = create(:commit_comment, user: collab)
      assert comment.async_minimizable_by?(collab).sync
    end

    test "returns false for user without write access if minimizing other users comment" do
      collab = create(:user)
      comment = create(:commit_comment)
      repo = comment.repository
      repo.add_member(collab, action: :read)
      refute comment.async_minimizable_by?(collab).sync
    end

    if GitHub.organization_moderators_enabled?
      test "returns true for organization moderator" do
        org_comment = create(:commit_comment, {
          user: @user2,
          repository: @org_owned_repo,
          commit_id: @commit2,
          path: "color.js",
          body: "Old body",
        })

        @org.moderation.add_moderator(@org_member, actor: @org.admin)
        assert @org.moderator?(@org_member)
        assert org_comment.async_minimizable_by?(@org_member).sync
      end

      test "returns false for organization moderator in private repo" do
        @org_owned_repo.update!(public: false)
        assert_predicate @org_owned_repo, :private?
        @org_owned_repo.add_member(@user2, action: :read)
        org_comment = create(:commit_comment, {
          user: @user2,
          repository: @org_owned_repo,
          commit_id: @commit2,
          path: "color.js",
          body: "Old body",
        })

        @org.moderation.add_moderator(@org_member, actor: @org.admin)
        assert @org.moderator?(@org_member)
        refute org_comment.async_minimizable_by?(@org_member).sync
      end
    end

    unless GitHub.enterprise?
      test "returns false for the Actions App on a public repo when it does not have permission" do
        random_repo = create(:public_repository, name: "random-repo", from_example: :commit_comments)
        comment_repo = create(:public_repository, name: "comment-repo", from_example: :commit_comments)

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "contents" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "contents" => :write },
        )

        comment = create :commit_comment, user: scoped_installation.bot, repository: comment_repo,
          position: 0, path: "color.js", commit_id: @commit2

        random_installation = make_integration_installation(
          integration: @actions_app,
          repository: random_repo,
          permissions: { "contents" => :write },
        )

        random_scoped_installation = make_scoped_integration_installation(
          parent: random_installation,
          repositories: [random_repo],
          permissions: { "contents" => :write },
        )

        refute comment.async_minimizable_by?(random_scoped_installation.bot).sync
      end

      test "returns true for the Actions App on a public repo when it has permission" do
        comment_repo = create(:public_repository, name: "comment-repo")

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "contents" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "contents" => :write },
        )

        comment = create :commit_comment, user: scoped_installation.bot, repository: comment_repo,
          position: 0, path: "color.js", commit_id: @commit2

        assert comment.async_minimizable_by?(scoped_installation.bot).sync
      end
    end
  end

  context "#async_viewer_can_update?" do
    test "returns whether the given user can edit the comment" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })

      admin = create :staff_admin_user

      assert comment.async_viewer_can_update?(@owner).sync
      assert comment.async_viewer_can_update?(@user2).sync
      refute comment.async_viewer_can_update?(@watcher).sync
      refute comment.async_viewer_can_update?(admin).sync

      comment.commit.lock(@owner)

      # Find a new object so that we don't keep any cached ivars around
      comment = CommitComment.find comment.id

      assert comment.async_viewer_can_update?(@owner).sync
      refute comment.async_viewer_can_update?(@user2).sync
      refute comment.async_viewer_can_update?(@watcher).sync
      refute comment.async_viewer_can_update?(admin).sync
    end

    test "is false for non-owner author when interaction limits are enabled" do
      interaction = RepositoryInteractionAbility.new(@repo)
      interaction.set_ability(:collaborators_only, @owner)

      refute @comment2_3.async_viewer_can_update?(@user).sync
    end

    test "is true for owner when interaction limits are enabled" do
      interaction = RepositoryInteractionAbility.new(@repo)
      interaction.set_ability(:collaborators_only, @owner)

      assert @comment2_3.async_viewer_can_update?(@owner).sync
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })

      repo   = @repo
      owner  = repo.owner
      collab = create(:user)
      author = @user2
      user   = create(:user)
      staff  = create(:staff_admin_user)

      admin = create :staff_admin_user

      assert_equal [], comment.async_viewer_cannot_update_reasons(@owner).sync
      assert_equal [], comment.async_viewer_cannot_update_reasons(@user2).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(@watcher).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(admin).sync

      # owner has blocked author
      repo.owner.block(author)
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(collab).sync
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

      comment.commit.lock(@owner)

      # Find a new object so that we don't keep any cached ivars around
      comment = CommitComment.find comment.id

      assert_equal [], comment.async_viewer_cannot_update_reasons(@owner).sync
      assert_equal [:locked], comment.async_viewer_cannot_update_reasons(@user2).sync
      assert_equal [:locked, :insufficient_access], comment.async_viewer_cannot_update_reasons(@watcher).sync
      assert_equal [:locked, :insufficient_access], comment.async_viewer_cannot_update_reasons(admin).sync
    end
  end

  context "#async_viewer_can_delete?" do
    test "returns whether the given user can delete the comment" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })

      admin = create :staff_admin_user

      assert comment.async_viewer_can_delete?(@owner).sync
      assert comment.async_viewer_can_delete?(@user2).sync
      refute comment.async_viewer_can_delete?(@watcher).sync
      assert comment.async_viewer_can_delete?(admin).sync

      comment.commit.lock(@owner)

      # Find a new object so that we don't keep any cached ivars around
      comment = CommitComment.find comment.id

      assert comment.async_viewer_can_delete?(@owner).sync
      refute comment.async_viewer_can_delete?(@user2).sync
      refute comment.async_viewer_can_delete?(@watcher).sync
      assert comment.async_viewer_can_delete?(admin).sync
    end

    test "owner can delete blocked user comments" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })

      author = comment.user
      owner = comment.repository.owner
      owner.block(author)
      assert comment.async_viewer_can_delete?(owner).sync
    end

    test "owner can delete blocking user comments" do
      comment = create(:commit_comment, {
        user: @user2,
        repository: @repo,
        commit_id: @commit2,
        path: "color.js",
        body: "Old Body",
      })

      author = comment.user
      owner = comment.repository.owner
      author.block(owner)
      assert comment.async_viewer_can_delete?(owner).sync
    end
  end

  context "Deleting a CommitComment" do
    test "instruments a commit_comment.destroy event" do
      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")

      events = subscribe "commit_comment.destroy"
      comment.stubs(:modifying_user).returns(@user2)
      comment.destroy
      expected_payload = {
        spammy: comment.spammy?,
        allowed: false,
        body: comment.body,
        author: @user2.to_s,
        author_id: @user2.id,
        commit_comment_id: comment.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @user2.to_s,
        actor_id: @user2.id,
      }

      assert event = events.pop, "expected an instrumenation event"
      assert_equal expected_payload, event.payload
    end

    test "instruments a commit_comment.destroy event in an org" do
      @repo.organization = create(:organization)
      assert @repo.in_organization?

      comment = create(:commit_comment, user: @user2, repository: @repo,
        commit_id: @commit2, path: "color.js", body: "Old Body")

      events = subscribe "commit_comment.destroy"
      comment.stubs(:modifying_user).returns(@user2)
      comment.destroy
      expected_payload = {
        spammy: comment.spammy?,
        allowed: false,
        body: comment.body,
        author: @user2.to_s,
        author_id: @user2.id,
        commit_comment_id: comment.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @user2.to_s,
        actor_id: @user2.id,
        org: @repo.organization.name,
        org_id: @repo.organization.id,
      }

      assert event = events.pop, "expected an instrumenation event"
      assert_equal expected_payload, event.payload
    end
  end

  context "When creating not really spammy-looking CommitComment" do
    test "doesn't flag you as a spammer if your comment isn't actually spammy-looking" do
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      GitHub::SpamChecker.stubs(:test_comment).returns(nil)
      @user2.commit_comments.create(repository: @repo,
        commit_id: @commit2, path: "color.js", body: "totally innocent")

      assert !@user2.reload.spammy?
    end
  end

  context "issue references" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @issue   = create :issue, repository: @repo, user: @repo.owner
      @issue_2 = create :issue, repository: @repo, user: @repo.owner
    end

    test "creates references for issues" do
      assert @issue.events.reload.where(commit_id: @commit).empty?

      create :commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: "/cc ##{@issue.number}"

      refs = @issue.events.reload.where(commit_id: @commit)
      assert_equal 1, refs.count
      ref = refs.first
      assert_equal @repo.id, ref.commit_repository_id
    end

    test "creates references for multiple issues at once" do
      assert @issue.events.reload.where(commit_id: @commit).empty?
      assert @issue_2.events.reload.where(commit_id: @commit).empty?

      create :commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: "/cc ##{@issue.number} ##{@issue_2.number}"

      refs = @issue.events.reload.where(commit_id: @commit)
      assert_equal 1, refs.count
      ref = refs.first
      assert_equal @repo.id, ref.commit_repository_id

      refs = @issue_2.events.reload.where(commit_id: @commit)
      assert_equal 1, refs.count
      ref = refs.first
      assert_equal @repo.id, ref.commit_repository_id
    end

    # Related issue: https://github.com/github/discussions/issues/503
    test "ensures that reference_from_discussion was called appropriately" do
      body = "some text here"
      comment = create :commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: body
      discussion = create(:discussion)

      body += "\n\n/cc ##{discussion.number}"
      comment.body = body

      assert_nothing_raised do
        comment.save
      end
    end

    test "creates references for issues added in edit" do
      assert @issue.events.reload.where(commit_id: @commit).empty?
      assert @issue_2.events.reload.where(commit_id: @commit).empty?

      body = "some text here"
      comment = create :commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: body

      assert @issue.events.reload.where(commit_id: @commit).empty?

      body += "\n\n/cc ##{@issue.number}"
      comment.body = body
      comment.save

      refs = @issue.events.reload.where(commit_id: @commit)
      assert_equal 1, refs.count
      ref = refs.first
      assert_equal @repo.id, ref.commit_repository_id

      assert @issue_2.events.reload.where(commit_id: @commit).empty?

      body += "\nalso /cc ##{@issue_2.number}"
      comment.body = body
      comment.save

      refs = @issue_2.events.reload.where(commit_id: @commit)
      assert_equal 1, refs.count
      ref = refs.first
      assert_equal @repo.id, ref.commit_repository_id
    end

    test "uses the editing user (not the original user) permissions when editing" do
      @owner.update(plan: "medium")

      user = create(:user, plan: "medium")
      user_private_repo   = create(:private_repository, owner: user)
      owner_private_repo  = create(:private_repository, owner: @owner)
      user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
      owner_private_issue = create(:issue, repository: owner_private_repo, user: @owner)

      user_private_reference  = [user_private_repo.name_with_owner,  user_private_issue.number].join("#")
      owner_private_reference = [owner_private_repo.name_with_owner, owner_private_issue.number].join("#")

      body  = "Hooray! a comment with some references: "
      body += user_private_reference + " "
      body += owner_private_reference

      comment = create(:commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: body)

      assert_includes comment.body, "Hooray!"
      refute_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
      assert_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]

      body  = "Hooray! editing the comment with some references: "
      body += user_private_reference + " "
      body += owner_private_reference

      comment.update_body(body, user)
      comment = CommitComment.find(comment.id)

      assert_includes comment.body, "Hooray!"
      assert_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
      refute_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]
    end
  end

  context "#path" do
    test "is saved as nil is set as empty string" do
      comment = CommitComment.new path: ""

      assert_nil comment.read_attribute(:path)
    end

    test "returns nil if the comments path is saved as an empty string" do
      comment = create(:commit_comment, user: @owner, repository: @repo, commit_id: @commit, body: "test comment")
      CommitComment.where(id: comment.id).update_all(path: "")

      assert_nil comment.reload.path
    end
  end

  context "#notifications_thread" do
    test "its thread for notifications is the commit" do
      assert_equal @repo.commits.find(@commit2), @comment2_1.notifications_thread
    end
  end

  context "`with_pull_requests` scope" do
    test "joins pull requests to commit comments based on the given mapping" do
      ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
      commit = ref.append_commit({ message: "Add file1", committer: @repo.owner, committed_date: 100.minutes.ago.iso8601 }, @repo.owner) do |files|
        files.add("file1.txt", "line1\nline2\nline3\n")
      end

      issue = create(:issue, repository: @repo)
      pull = PullRequest.create_for(
        @repo,
        base: "master",
        head: ref.name,
        user: @owner,
        issue: issue,
      )

      comments = CommitComment.with_pull_requests({ pull.id => [@commit, @commit2] }).select([
        "`commit_comments`.*",
        "`pull_requests`.`id` as `pull_request_id`",
      ]).order(:id)

      assert_equal [
        [@comment2_1.id, @commit2, pull.id],
        [@comment2_2.id, @commit2, pull.id],
        [@comment2_3.id, @commit2, pull.id],
        [@comment2_4.id, @commit2, pull.id],
      ], comments.map { |comment| [comment.id, comment.commit_id, T.unsafe(comment).pull_request_id] }
    end
  end

  unless GitHub.enterprise?
    test "fails validation if user is comment blocked" do
      User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
      User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
      begin
        comment = create :commit_comment
      rescue ActiveRecord::RecordInvalid => e
        assert_includes e.message, "suspended for 1 day"
      end
    end
  end

  context "restricted by repository comment checks" do
    context "sock puppet ban" do
      test "disallows commenting from 0-day accounts" do
        Repository.stubs(:sockpuppet_disallowed_enabled?).returns(true)

        begin
          comment = create :commit_comment
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "new users"
        end
      end

      test "allows non-0-day accounts" do
        Repository.stubs(:sockpuppet_disallowed_enabled?).returns(true)

        old_user = create(:user, created_at: 3.days.ago)
        comment = create(:commit_comment, user: old_user)
        assert comment.valid?
      end
    end

    context "prior contributor" do
      test "disallows commenting for non-contributors" do
        RepositoryInteractionAbility.any_instance.stubs(:contributors_only_enabled?).returns(true)

        begin
          comment = create(:commit_comment, repository: @contributor_repository)
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "prior contributors only"
        end
      end

      test "allows a prior contributor to comment" do
        RepositoryInteractionAbility.any_instance.stubs(:contributors_only_enabled?).returns(true)

        contributor = create(:user)
        CommitContribution.create(repository: @contributor_repository, user: contributor)
        comment = create(:commit_comment, user: contributor, repository: @contributor_repository)
        assert comment.valid?
      end
    end

    context "collaborator" do
      test "disallows commenting for non-collaborators" do
        RepositoryInteractionAbility.any_instance.stubs(:collaborators_only_enabled?).returns(true)

        begin
          comment = create(:commit_comment, repository: @collaborator_repository)
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "collaborators only"
        end
      end

      test "disallows editing a comment for non-collaborators" do
        comment = create(:commit_comment, user: create(:user))

        interaction = RepositoryInteractionAbility.new(comment.repository)
        interaction.set_ability(:collaborators_only, comment.repository.owner)

        refute comment.update_body("hello!", comment.user)

        assert_includes comment.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end

      test "allows a collaborator to comment" do
        RepositoryInteractionAbility.any_instance.stubs(:collaborators_only_enabled?).returns(true)

        collaborator = create(:user)
        @collaborator_repository.add_member(collaborator)
        comment = create(:commit_comment, repository: @collaborator_repository, user: collaborator)
        assert comment.valid?
      end

      test "allows a collaborator to edit a comment" do
        comment = create(:commit_comment, user: create(:user))

        interaction = RepositoryInteractionAbility.new(comment.repository)
        interaction.set_ability(:collaborators_only, comment.repository.owner)

        collaborator = create(:user)
        comment.repository.add_member(collaborator)

        assert comment.update_body("hello!", collaborator)
      end
    end
  end unless GitHub.enterprise?

  context "unminimize a comment" do
    test "only staff can unminimize staff comment" do
      @comment.update(comment_hidden_by: ROLES[:minimized_by_staff])
      refute @comment.async_unminimizable_by?(@author).sync
      refute @comment.async_unminimizable_by?(@maintainer).sync
      assert @comment.async_unminimizable_by?(@staff_user).sync
    end

    test "maintainer & staff can unminimize maintainer-minimized comment" do
      @comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])
      assert @comment.async_unminimizable_by?(@maintainer).sync
      assert @comment.async_unminimizable_by?(@staff_user).sync
      refute @comment.async_unminimizable_by?(@author).sync
    end

    test "maintainer, staff & author can unminimize author-minimized comment" do
      comment_author = create(:verified_user)
      author_comment = create :commit_comment, user: comment_author, repository: @repo,
                        position: 0, path: "color.js", commit_id: @commit3
      author_comment.update(comment_hidden_by: ROLES[:minimized_by_author])

      assert author_comment.async_unminimizable_by?(@maintainer).sync
      assert author_comment.async_unminimizable_by?(@staff_user).sync
      refute author_comment.async_unminimizable_by?(@author).sync
      assert author_comment.async_unminimizable_by?(comment_author).sync
    end

    test "stores the right comment hidden by value" do
      author_minimized_comment = create :commit_comment, user: @maintainer, repository: @repo,
                                        position: 40, path: "color.js", commit_id: @commit3
      author_minimized_comment.set_minimized(@author, "reason", "spam", @author, staff = false)

      maintainer_minimized_comment = create :commit_comment, user: @owner, repository: @repo,
                                            position: 41, path: "color.js", commit_id: @commit3
      maintainer_minimized_comment.set_minimized(@maintainer, "reason", "spam", @author, staff = false)

      staff_minimized_comment = create :commit_comment, user: @owner, repository: @repo,
                                       position: 0, path: "color.js", commit_id: @commit3
      staff_minimized_comment.set_minimized(@staff_user, "reason", "spam", @author, staff = true)


      assert_equal("minimized_by_author", author_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_maintainer", maintainer_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_staff", staff_minimized_comment.comment_hidden_by)
    end
  end

  context "mannequins" do
    test "commits can be created" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)

      assert_raises ActiveRecord::RecordInvalid do
        invalid_comment = create(:commit_comment, user: @user2, repository: @repo,
          commit_id: @commit2, path: "color.js")
      end

      valid_comment = create(:commit_comment, user: @mannequin, repository: @repo,
        commit_id: @commit2, path: "color.js")

      assert valid_comment
    end
  end

  test "is deleted with repository" do
    comment = create(:commit_comment, user: @org_admin, repository: @org_repo, body: "body", commit_id: @commit)
    other_comment = create(:commit_comment, user: @user2, repository: @org_owned_repo, body: "body", commit_id: @commit2)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @org_repo
      config.expect_destroyed = [comment]
      config.expect_not_destroyed = [other_comment]
    end
  end
end

class CommitCommentRateLimitingTest < GitHub::TestCase
  setup_once do
    enable_cache_storage
  end

  setup do
    enable_content_creation_rate_limiting
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  test "comments are rate limited" do
    user = create(:user)
    6.times do |_i|
      comment = create :commit_comment, user: user
      assert_empty comment.errors
    end

    begin
      create :commit_comment, user: user
    rescue ActiveRecord::RecordInvalid => e
      assert_match "submitted too quickly", e.message
    end
  end
end
