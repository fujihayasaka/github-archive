# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionLockingDependencyTest < GitHub::TestCase
  include DiscussionsTestHelper
  include HydroTestHelpers

  fixtures do
    create_discussions_authz_fixtures

    @public_discussion = create(:discussion, :question, repository: @repo)
    private_discussion_author = create(:verified_user)
    @private_repo.add_member(private_discussion_author)
    @private_discussion = create(:discussion,
      repository: @private_repo,
      user: private_discussion_author,
    )

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_without_default_permission_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_private_repo,
    )

    @business_internal_discussion = create(:discussion, :question,
      repository: @business_internal_repo,
    )

    @spammer = create(:spammy_user, :verified)
    @staff = create(:verified_user, :staff)

    User.create_ghost
  end

  setup do
    @matrix = DiscussionsTestHelper::AccessMatrix.new(self)

    @matrix.setup_subjects(
      repo: @public_discussion,
      private_repo: @private_discussion,
      org_repo: @org_discussion,
      org_private_repo: @org_private_discussion,
      org_without_default_permission_repo: @org_without_default_permission_repo_discussion,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_discussion,
      business_internal_repo: @business_internal_discussion,
    )
  end

  context "#locked_for? and #async_locked_for?" do
    test "true when discussion is locked and user lacks repo write access" do
      @public_discussion.lock(actor: @owner, allow_reactions: false)
      assert @public_discussion.locked_for?(@rando)
      assert @public_discussion.async_locked_for?(@rando).sync
    end

    test "false when discussion is locked and user has repo write access" do
      @public_discussion.lock(actor: @owner, allow_reactions: false)
      refute @public_discussion.locked_for?(@owner)
      refute @public_discussion.async_locked_for?(@owner).sync
    end

    test "true when discussion is locked with reactions allowed and user lacks repo write access" do
      @public_discussion.lock(actor: @owner, allow_reactions: true)
      assert @public_discussion.locked_for?(@rando)
      assert @public_discussion.async_locked_for?(@rando).sync
    end

    test "false when discussion is not locked" do
      refute @public_discussion.locked_for?(@rando)
      refute @public_discussion.async_locked_for?(@rando).sync
    end
  end

  context "#reactions_locked_for? and #async_reactions_locked_for?" do
    test "true when discussion is locked and user lacks repo write access" do
      @public_discussion.lock(actor: @owner, allow_reactions: false)
      assert @public_discussion.reactions_locked_for?(@rando)
      assert @public_discussion.async_reactions_locked_for?(@rando).sync
    end

    test "false when discussion is locked and user has repo write access" do
      @public_discussion.lock(actor: @owner, allow_reactions: false)
      refute @public_discussion.reactions_locked_for?(@owner)
      refute @public_discussion.async_reactions_locked_for?(@owner).sync
    end

    test "false when discussion is locked with reactions allowed" do
      @public_discussion.lock(actor: @owner, allow_reactions: true)
      refute @public_discussion.reactions_locked_for?(@rando)
      refute @public_discussion.async_reactions_locked_for?(@rando).sync
    end

    test "false when discussion is unlocked" do
      refute @public_discussion.reactions_locked_for?(@rando)
      refute @public_discussion.async_reactions_locked_for?(@rando).sync
    end
  end

  context "#lockable_by? and #async_lockable_by?" do
    test "requires write+" do
      @matrix.user_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for GitHub staff" do
      assert @public_discussion.lockable_by?(@staff)
      assert @public_discussion.async_lockable_by?(@staff).sync
    end

    if GitHub.email_verification_enabled?
      test "false for user without verified email address" do
        unverified = create(:user, :staff)
        refute @public_discussion.lockable_by?(unverified)
        refute @public_discussion.async_lockable_by?(unverified).sync
      end
    else
      test "true for user without verified email address" do
        unverified = create(:user, :staff)
        assert @public_discussion.lockable_by?(unverified)
        assert @public_discussion.async_lockable_by?(unverified).sync
      end
    end

    test "false when repository is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.lockable_by?(@staff)
      refute @public_discussion.async_lockable_by?(@staff).sync
    end

    test "false when setting is disabled" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.lockable_by?(@staff)
      refute @public_discussion.async_lockable_by?(@staff).sync
    end

    test "false for anonymous user" do
      refute @public_discussion.lockable_by?(nil)
      refute @public_discussion.async_lockable_by?(nil).sync
    end

    test "requires maintain+ when discussions is announcement" do
      matrix_announcement_discussions

      @matrix.user_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: true,
        admin: true,
      )
    end

    test "requires discussions: write for bots" do
      @matrix.bot_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for bots when discussions are off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot user of integration when repo is locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot user of integration when repo is archived" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :lockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#unlockable_by? and #async_unlockable_by?" do
    test "true for user with write+ access when discussion is locked" do
      matrix_lock_discussions

      @matrix.user_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for GitHub staff when discussion is locked" do
      matrix_lock_discussions

      assert @public_discussion.unlockable_by?(@staff)
      assert @public_discussion.async_unlockable_by?(@staff).sync
    end

    if GitHub.email_verification_enabled?
      test "false for user without verified email address" do
        matrix_lock_discussions
        unverified = create(:user, :staff)
        refute @public_discussion.unlockable_by?(unverified)
        refute @public_discussion.async_unlockable_by?(unverified).sync
      end
    else
      test "true for user without verified email address" do
        matrix_lock_discussions
        unverified = create(:user, :staff)
        assert @public_discussion.unlockable_by?(unverified)
        assert @public_discussion.async_unlockable_by?(unverified).sync
      end
    end

    test "false when repository is archived" do
      matrix_lock_discussions
      matrix_archive_repos

      @matrix.user_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.unlockable_by?(@staff)
      refute @public_discussion.async_unlockable_by?(@staff).sync
    end

    test "false when setting is disabled" do
      matrix_lock_discussions
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.unlockable_by?(@staff)
      refute @public_discussion.async_unlockable_by?(@staff).sync
    end

    test "false for anonymous users" do
      @public_discussion.lock(actor: @owner)
      refute @public_discussion.unlockable_by?(nil)
      refute @public_discussion.async_unlockable_by?(nil).sync
    end

    test "true for bot user of integrations with write permissions" do
      matrix_lock_discussions

      @matrix.bot_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for bot users of integrations on repo with discussions off" do
      matrix_lock_discussions
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repo locked for migration" do
      matrix_lock_discussions
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on archived repo" do
      matrix_lock_discussions
      matrix_archive_repos

      @matrix.bot_scenarios(
        :unlockable_by?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#lock" do
    test "creates an associated timeline event" do
      @public_discussion.lock(actor: @owner)

      event = @public_discussion.events.last
      assert_equal @owner, event.actor
      assert_predicate event, :locked?
    end

    test "modifies the discussion's state" do
      @public_discussion.lock(actor: @owner)

      assert_predicate @public_discussion, :locked?
      refute_predicate @public_discussion, :allow_reactions?
    end

    test "modifies the allow_reactions field when discussion locked with reactions allowed" do
      @public_discussion.lock(actor: @owner, allow_reactions: true)

      assert_predicate @public_discussion, :allow_reactions?
    end

    test "instruments hydro event", skip_enterprise: true do
      Timecop.freeze do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        # default fixture uses an open ended
        discussion = create(:discussion)

        reset_hydro

        # use a different user to the lock the discussion
        editor = create(:verified_user)
        discussion.repository.add_member(editor, action: :write)
        discussion.repository.add_member(discussion.user, action: :write)
        discussion.lock(actor: editor)

        message_locked_discussion = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          actor_id: editor.id,
          actor: Hydro::EntitySerializer.user(editor),
          discussion_id: discussion.id,
          discussion: Hydro::EntitySerializer.discussion(discussion),
          lock_status: :LOCK_STATUS_LOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_locked_discussion, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end
  end

  context "#unlock" do
    test "creates an associated timeline event" do
      @public_discussion.lock(actor: @owner)
      @public_discussion.unlock(actor: @owner)

      event = @public_discussion.events.last
      assert_equal @owner, event.actor
      assert_predicate event, :unlocked?
    end

    test "modifies the discussion's state" do
      @public_discussion.lock(actor: @owner)
      @public_discussion.unlock(actor: @owner)

      refute_predicate @public_discussion, :locked?
      assert_predicate @public_discussion, :allow_reactions?
      assert_predicate @public_discussion, :open?
    end

    test "modifies the discussion's state when locked with reactions allowed" do
      @public_discussion.lock(actor: @owner, allow_reactions: true)
      @public_discussion.unlock(actor: @owner)

      refute_predicate @public_discussion, :locked?
      assert_predicate @public_discussion, :allow_reactions?
      assert_predicate @public_discussion, :open?
    end

    test "instruments hydro event", skip_enterprise: true do
      Timecop.freeze do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        # default fixture uses an open ended
        discussion = create(:discussion)
        discussion.repository.add_member(discussion.user, action: :write)
        discussion.lock(actor: discussion.user)

        reset_hydro

        # use the original creator of the discussion to unlock it
        discussion.unlock(actor: discussion.user)

        message_unlocked_discussion = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          actor_id: discussion.user.id,
          actor: Hydro::EntitySerializer.user(discussion.user),
          discussion_id: discussion.id,
          discussion: Hydro::EntitySerializer.discussion(discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_unlocked_discussion, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end
  end

  context "#active_lock_reason" do
    test "returns resolved by default when locked" do
      @public_discussion.lock(actor: @owner)
      assert_equal "resolved", @public_discussion.active_lock_reason

      expected_lock_reason_msg = <<-'MSG'
        Didn't find #{@public_discussion.active_lock_reason} as a valid lock reason.
        Did you remove a lock reason for issues? If so, please update Discussion#active_lock_reason
        to have a new value to use as the default lock reason for discussions.
      MSG
      assert_includes(Issue::LOCK_REASONS, @public_discussion.active_lock_reason, expected_lock_reason_msg)
    end

    test "returns nil if not locked" do
      assert_nil @public_discussion.active_lock_reason
    end
  end

  private

  def matrix_lock_discussions
    @matrix.each_subject do |discussion|
      discussion.lock(actor: discussion.repository.in_organization? ? @admin : @owner)
    end
  end

  def matrix_turn_off_discussions
    @matrix.each_repo { |repo, admin| repo.turn_off_discussions(actor: admin, instrument: false) }
  end

  def matrix_lock_repos_for_migration
    @matrix.each_repo { |repo| repo.lock_for_migration }
  end

  def matrix_archive_repos
    @matrix.each_repo { |repo| repo.set_archived }
  end

  def matrix_announcement_discussions
    @matrix.each_subject do |discussion|
      discussion.category.update(supports_announcements: true)
    end
  end
end
