# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentTest < GitHub::TestCase
  include HydroTestHelpers
  include DiscussionsTestHelper
  include StringFromBinaryTestHelper
  ROLES = GitHub::MinimizeComment::ROLES

  fixtures do
    create_discussions_authz_fixtures

    @unanswered_discussion = create(:discussion, :question, repository: @repo)
    @comment = Timecop.freeze(1.day.ago) do
      create(:discussion_comment, repository: @repo, discussion: @unanswered_discussion,
        body: "This is a comment on a discussion with no answer.")
    end

    @private_author = create(:verified_user)
    @private_repo.add_member(@private_author)
    @private_discussion = create(:discussion, :question, repository: @private_repo, user: @private_author)
    @private_comment = create(:discussion_comment, repository: @private_repo, discussion: @private_discussion)

    @org_discussion = create(:discussion, :question, repository: @org_repo)
    @org_comment = create(:discussion_comment, repository: @org_repo, discussion: @org_discussion)

    @org_private_discussion = create(:discussion, :question, repository: @org_private_repo)
    @org_private_comment = create(:discussion_comment,
      repository: @org_private_repo, discussion: @org_private_discussion)

    @answered_discussion = create(:discussion, :question, repository: @repo)
    @nonanswer = Timecop.freeze(2.days.ago) do
      create(:discussion_comment, repository: @repo, discussion: @answered_discussion)
    end
    @answer = create(:discussion_comment, repository: @repo, discussion: @answered_discussion,
      body: "This is the correct answer.")
    @answered_discussion.chosen_comment = @answer
    @answered_discussion.save!

    @parent_comment = create(:discussion_comment, discussion: @unanswered_discussion, repository: @repo)
    @child_comment = create(:discussion_comment,
      discussion: @unanswered_discussion,
      parent_comment: @parent_comment,
      repository: @repo,
    )

    @minimized_comment = create(:discussion_comment, :minimized, discussion: @unanswered_discussion)

    @answered_org_discussion = create(:discussion, :question, repository: @org_repo)
    @org_answer = create(:discussion_comment, repository: @org_repo, discussion: @answered_org_discussion)
    @answered_org_discussion.chosen_comment = @org_answer
    @answered_org_discussion.save!

    @org_without_default_permission_repo_discussion = create(:discussion, :question,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_discussion = create(:discussion, :question,
      repository: @org_without_default_permission_private_repo,
    )
    @org_without_default_permission_repo_comment = create(:discussion_comment,
      discussion: @org_without_default_permission_repo_discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_comment = create(:discussion_comment,
      discussion: @org_without_default_permission_private_repo_discussion,
      repository: @org_without_default_permission_private_repo,
    )

    @business_internal_discussion = create(:discussion, repository: @business_internal_repo)
    @business_internal_comment = create(:discussion_comment,
      discussion: @business_internal_discussion, repository: @business_internal_repo)

    @spammer = create(:spammy_user, :verified)
    @staff = create(:user, :staff)
    @staff_user = create(:staff_admin_user)
  end

  setup do
    @matrix = DiscussionsTestHelper::AccessMatrix.new(self)
    @matrix.setup_subjects(
      repo: @comment,
      private_repo: @private_comment,
      org_repo: @org_comment,
      org_private_repo: @org_private_comment,
      org_without_default_permission_repo: @org_without_default_permission_repo_comment,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_comment,
      business_internal_repo: @business_internal_comment,
    )
    GitHub.flipper[:login_revocation_for_credential_in_url].disable
  end

  context "#dom_id" do
    test "returns nil for new discussion comment that hasn't been saved" do
      assert_nil DiscussionComment.new.dom_id
    end

    test "returns a plain-text identifier for existing discussion comment" do
      assert_equal "discussioncomment-#{@comment.id}", @comment.dom_id
    end

    test "returns different values for different discussion comments" do
      result1 = @comment.dom_id
      result2 = @org_comment.dom_id
      refute_equal result1, result2
    end

    test "returns different value than #dom_id for a discussion with the same ID" do
      Discussion.any_instance.stubs(:id).returns(@comment.id)
      refute_equal @comment.dom_id, @unanswered_discussion.dom_id
    end
  end

  context ".dom_id" do
    test "returns given comment ID prefixed with string to represent a comment in the page" do
      assert_equal "discussioncomment-123", DiscussionComment.dom_id("123")
      assert_equal "discussioncomment-456", DiscussionComment.dom_id(456)
    end
  end

  context "#permalink_id" do
    test "returns nil for new discussion comment that hasn't been saved" do
      assert_nil DiscussionComment.new.permalink_id
    end

    test "includes the discussion comment's dom_id" do
      assert_equal "#{@comment.dom_id}-permalink", @comment.permalink_id
    end
  end

  context "#minimization_reason_for" do
    test "says user is spammy to site admin" do
      spammy_comment = create(:spammy_discussion_comment, comment_hidden_classifier: "spam")
      assert_equal "This comment and user were marked as spammy.",
        spammy_comment.minimization_reason_for(viewer: @staff)
    end if GitHub.spamminess_check_enabled?

    test "does not say user is spammy to regular user" do
      spammy_comment = create(:spammy_discussion_comment, comment_hidden_classifier: "spam")
      assert_equal "This comment was marked as spam.",
        spammy_comment.minimization_reason_for(viewer: @private_author)
    end if GitHub.spamminess_check_enabled?
  end

  context "hydro update event" do
    test "a hydro event is triggered with the correct payload on update for a user content editable attribute" do
      SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

      discussion_comment = create(:discussion_comment, discussion: @answered_discussion)
      discussion_comment.reload

      discussion_comment.update_body("new body", @owner)
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        discussion_comment: Hydro::EntitySerializer.discussion_comment(discussion_comment.reload),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(
          GitHub.context[:spamurai_form_signals],
        ),
        specimen_body: Hydro::EntitySerializer.specimen_data("new body"),
        actor: Hydro::EntitySerializer.user(@owner),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@owner),
        author: Hydro::EntitySerializer.user(discussion_comment.user),
        discussion: Hydro::EntitySerializer.discussion(discussion_comment.discussion),
        discussion_author: Hydro::EntitySerializer.user(discussion_comment.discussion.user),
        feature_flags: []
      }

      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentUpdate")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentUpdate")
    end
  end

  context "#author_display_login" do
    test "returns the display login of the comment's author" do
      author = create(:verified_user)
      author.update_attribute(:display_login, "HelloWorld")
      comment = create(:discussion_comment, discussion: @unanswered_discussion, repository: @repo, user: author)
      assert_equal "HelloWorld", comment.author_display_login
    end

    test "returns the display login of the ghost user when author has been deleted" do
      comment = create(:discussion_comment, discussion: @unanswered_discussion, repository: @repo)
      comment.user.delete
      assert_equal User.ghost.display_login, comment.reload.author_display_login
    end
  end

  context "#repository_owner_login" do
    test "returns login of the owner of the repository the discussion comment belongs to" do
      assert_equal @owner.login, @comment.repository_owner_login
    end
  end

  context "#repository_name" do
    test "returns the name of the repository the discussion comment belongs to" do
      assert_equal @repo.name, @comment.repository_name
    end
  end

  context "#discussion_number" do
    test "returns the number of the discussion the comment is on" do
      assert_equal @answered_org_discussion.number, @org_answer.discussion_number
    end
  end

  test "#viewer_can_delete_user_content_edits? allowed with write+" do
    @matrix.user_scenarios(
      :viewer_can_delete_user_content_edits?,
      none: false,
      read: false,
      triage: false,
      write: true,
      maintain: true,
      admin: true,
    )
  end

  context "websocket" do
    test "triggers websocket message for discussion timeline when creating top-level comment" do
      Timecop.freeze do
        # Discussion timeline channel updated to signify new comment
        discussion_channel = GitHub::WebSocket::Channels.discussion(@unanswered_discussion)
        discussion_timeline_channel = GitHub::WebSocket::Channels.discussion_timeline(@unanswered_discussion)
        discussion_summary_channel = GitHub::WebSocket::Channels.discussion_summary(@unanswered_discussion)

        # Discussion summary update channel updated to signify new comment
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_summary_channel, kind_of(Hash)).returns([]).once

        # Discussion timeline channel updated to signify new comment
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_timeline_channel, kind_of(Hash)).returns([]).once

        # Discussion gets its updated_at changed when the comment is made
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_channel, kind_of(Hash)).returns([]).once

        create(:discussion_comment, discussion: @unanswered_discussion)
      end
    end

    test "triggers websocket message for comment thread and discussion summary when creating child comment" do
      Timecop.freeze do
        # Discussion channel updated to signify new child comment (with gid specifying the parent comment)
        discussion_channel = GitHub::WebSocket::Channels.discussion(@unanswered_discussion)
        discussion_summary_channel = GitHub::WebSocket::Channels.discussion_summary(@unanswered_discussion)
        parent_gid = @comment.global_relay_id

        # Discussion summary update channel updated to signify new child comment
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_summary_channel, has_entries(gid: @unanswered_discussion.global_relay_id)).
          returns([]).once

        # Discussion channel updated to signify new child comment (with gid specifying the parent comment)
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_channel, has_entries(gid: parent_gid)).returns([]).once

        # Discussion gets its updated_at changed when the comment is made
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_channel, has_entries(gid: @unanswered_discussion.global_relay_id)).
          returns([]).once

        create(:discussion_comment, discussion: @unanswered_discussion, parent_comment: @comment)
      end
    end

    test "triggers websocket message for comment thread when deleting child comment" do
      Timecop.freeze do
        # Discussion channel updated to signify removed child comment (with gid specifying the parent comment)
        discussion_channel = GitHub::WebSocket::Channels.discussion(@unanswered_discussion)
        discussion_summary_channel = GitHub::WebSocket::Channels.discussion_summary(@unanswered_discussion)

        # Discussion summary update channel updated to signify new comment
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_summary_channel, has_entries(gid: @unanswered_discussion.global_relay_id)).
          returns([]).once

        # Discussion channel updated to signify removed child comment (with gid specifying the child comment)
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_channel, has_entries(gid: @child_comment.parent_comment.global_relay_id)).returns([]).once

        # Discussion gets comment_count changed
        GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@unanswered_discussion, discussion_channel, has_entries(gid: @unanswered_discussion.global_relay_id)).returns([]).once

        assert @child_comment.destroy
      end
    end
  end

  context "#can_be_commented_on?" do
    test "true for top-level non-minimized comment" do
      assert_predicate @org_answer, :can_be_commented_on?
    end

    test "false for child comment" do
      refute_predicate @child_comment, :can_be_commented_on?
    end

    test "false for top-level minimized comment" do
      hidden_comment = create(:discussion_comment, discussion: @unanswered_discussion, comment_hidden: true)
      refute_predicate hidden_comment, :can_be_commented_on?
    end
  end

  context "#wiped?" do
    test "true when deleted_at is set" do
      wiped_comment = create(:discussion_comment, :wiped)
      refute_nil wiped_comment.deleted_at, "expect deleted_at to be present for this test"
      assert_predicate wiped_comment, :wiped?
    end

    test "false when deleted_at is empty" do
      assert_nil @org_comment.deleted_at, "expect deleted_at to be nil for this test"
      refute_predicate @org_comment, :wiped?
    end
  end

  context "chosen_answers scope" do
    test "includes chosen comments" do
      results = DiscussionComment.chosen_answers

      assert_includes results, @answer
      assert_includes results, @org_answer
    end

    test "excludes non-chosen comments" do
      results = DiscussionComment.chosen_answers

      refute_includes results, @org_comment
      refute_includes results, @comment
    end
  end

  context "vote scopes" do
    test "upvotes only returns upvotes" do
      discussion = create(:discussion)
      comment = create(:discussion_comment, discussion: discussion)
      upvote = create(:discussion_comment_vote, upvote: true, comment: comment)
      user = create(:verified_user)
      comment.repository.add_member(user, action: :write)

      assert_includes comment.upvotes, upvote
    end

    test "deletes votes when comment is deleted" do
      # after_create hook will auto-create an upvote
      discussion = create(:discussion, user: @owner)
      comment = create(:discussion_comment, discussion: discussion)
      vote = comment.votes.first

      assert_difference("DiscussionCommentVote.count", -1) do
        perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
          comment.destroy
        end
      end

      refute DiscussionCommentVote.exists?(vote.id)
    end
  end

  context "#comment_count" do
    test "returns 0 when no child comments" do
      assert_equal 0, @org_comment.comment_count
    end

    test "returns count of nested comments when there are child comments" do
      create(:discussion_comment, parent_comment: @org_comment, discussion: @org_discussion)
      create(:discussion_comment, parent_comment: @org_comment, discussion: @org_discussion)

      assert_equal 2, @org_comment.comment_count
    end
  end

  context "#comments" do
    test "returns an empty list when comment has no children" do
      assert_empty @org_comment.comments
    end

    test "returns comments with the comment's ID as their parent comment ID" do
      child1 = create(:discussion_comment, parent_comment: @org_comment,
        discussion: @org_discussion)
      child2 = create(:discussion_comment, parent_comment: @org_comment,
        discussion: @org_discussion)

      result = @org_comment.comments

      assert_same_elements [child1, child2], result
    end
  end

  context "blocking users" do
    test "can be deleted even when blocked by discussion author" do
      @unanswered_discussion.user.block(@comment.user)
      assert @comment.deletable_by?(@comment.user)
      assert @comment.destroy
      refute DiscussionComment.exists?(@comment.id)
    end
  end

  context "edit comment permissions" do
    test "true for author of comment with read+" do
      assert_block = ->(comment, user) do
        comment.update!(user: user)
        assert_comment_modifiable(comment, user: user)
      end

      refute_block = ->(comment, user) do
        comment.update!(user: user)
        refute_comment_modifiable(comment, user: user)
      end

      @matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when comment has been wiped" do
      assert @parent_comment.wipe_or_destroy(@parent_comment.user)
      assert_predicate @parent_comment, :wiped?

      refute_comment_modifiable(@parent_comment, user: @owner)
    end

    test "false for author of comment without a verified email" do
      issue = create(:issue, repository: @repo, user: @unverified)
      discussion = create(:discussion, issue: issue, state: :converting, repository: @repo)
      comment = create(:discussion_comment, user: @unverified, discussion: discussion, repository: @repo)

      refute_comment_modifiable(comment, user: @unverified)
    end if GitHub.email_verification_enabled?

    test "false for anonymous user" do
      refute_comment_modifiable(@comment, user: nil)
    end

    test "false when user has been blocked by discussion author" do
      @unanswered_discussion.user.block(@comment.user)

      refute_comment_modifiable(@comment, user: @comment.user)
    end

    test "true for author of comment even when discussion author was deleted" do
      @unanswered_discussion.user.destroy
      @unanswered_discussion.reload

      assert_comment_modifiable(@comment, user: @comment.user, discussion: @unanswered_discussion)
    end

    test "requires triage+ for non-authors" do
      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_modifiable(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_modifiable(comment, user: user) },
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "requires triage+ when discussion is locked" do
      @matrix.each_subject { |comment| comment.discussion.stubs(:locked?).returns(true) }

      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_modifiable(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_modifiable(comment, user: user) },
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when repo does not have discussions setting on" do
      @org_repo.turn_off_discussions(actor: @admin, instrument: false)

      refute_comment_modifiable(@org_comment.reload, user: @writer)
    end

    test "false when org-owned repository is archived" do
      @org_repo.set_archived

      refute_comment_modifiable(@org_comment.reload, user: @admin)
    end

    test "false when user-owned repository is archived" do
      @repo.set_archived

      refute_comment_modifiable(@comment.reload, user: @owner)
    end

    context "when interaction limits are enabled" do
      test "false for author of the discussion if not a collaborator" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        refute_comment_modifiable(@org_comment, user: @org_comment.user)
      end

      test "true for author of the discussion if collaborator on the repo" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        assert_comment_modifiable(@org_comment, user: @writer)
      end
    end if GitHub.interaction_limits_enabled?

    test "integrations require install with discussions: write permissions" do
      @matrix.bot_scenarios_custom(
        assert_block: ->(comment, bot) { assert_comment_modifiable(comment, user: bot) },
        refute_block: ->(comment, bot) { refute_comment_modifiable(comment, user: bot) },
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for an integration on a wiped comment" do
      @parent_comment.wipe_or_destroy(@owner)

      refute_comment_modifiable(@parent_comment, user: @bot_repo_write)
    end

    test "false for an integration when the repo has turned off discussions" do
      @repo.turn_off_discussions(actor: @owner, instrument: false)

      refute_comment_modifiable(@comment.reload, user: @bot_repo_write)
    end

    test "false for an integration when the repo is locked" do
      @repo.lock_for_migration

      refute_comment_modifiable(@comment.reload, user: @bot_repo_write)
    end

    test "false for an integration when the repo is archived" do
      @repo.set_archived

      refute_comment_modifiable(@comment.reload, user: @bot_repo_write)
    end
  end

  context "#viewer_can_update?" do
    test "true for author of comment" do
      assert @comment.viewer_can_update?(@comment.user)
    end

    test "false for author of comment when repo is locked" do
      @repo.lock_for_migration
      refute @comment.viewer_can_update?(@comment.user)
    end

    test "false for author of comment when repo is archived" do
      @repo.remove(@repo.owner)
      refute @comment.reload.viewer_can_update?(@comment.user)
    end

    test "false for anonymous user" do
      refute @comment.viewer_can_update?(nil)
    end

    test "require triage+ for non-author" do
      @matrix.user_scenarios(
        :viewer_can_update?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when user has been blocked by discussion author" do
      @unanswered_discussion.user.block(@comment.user)

      refute @comment.viewer_can_update?(@comment.user)
    end

    test "false for author of the comment when interaction limits disallow them" do
      interaction = RepositoryInteractionAbility.new(@repo)
      interaction.set_ability(:collaborators_only, @repo.owner)

      refute @comment.viewer_can_update?(@comment.user)
    end
  end

  context "#can_mark_as_answer?" do
    test "false for author of comment" do
      refute @comment.can_mark_as_answer?(@comment.user)
      refute @comment.async_can_mark_as_answer?(@comment.user).sync
    end

    test "true for nested comment" do
      assert @child_comment.can_mark_as_answer?(@unanswered_discussion.user)
      assert @child_comment.async_can_mark_as_answer?(@unanswered_discussion.user).sync
    end

    test "false for minimized comment" do
      refute @minimized_comment.can_mark_as_answer?(@unanswered_discussion.user)
      refute @minimized_comment.async_can_mark_as_answer?(@unanswered_discussion.user).sync
    end

    test "requires triage+" do
      @matrix.user_scenarios(
        :can_mark_as_answer?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for discussion author" do
      assert @comment.can_mark_as_answer?(@unanswered_discussion.user)
      assert @comment.async_can_mark_as_answer?(@unanswered_discussion.user).sync
    end

    test "false for a wiped comment" do
      wiped_comment = create(:discussion_comment, :wiped, discussion: @unanswered_discussion)
      refute wiped_comment.can_mark_as_answer?(@unanswered_discussion.user)
      refute wiped_comment.async_can_mark_as_answer?(@unanswered_discussion.user).sync
    end

    if GitHub.organization_moderators_enabled?
      test "true for moderator" do
        moderator = create(:verified_user)
        @org.add_member(moderator)
        @org.moderation.add_moderator(moderator, actor: @org.admin)
        assert @org.moderator?(moderator)
        assert @org_comment.can_mark_as_answer?(moderator)
        assert @org_comment.async_can_mark_as_answer?(moderator).sync
      end
    end

    if GitHub.email_verification_enabled?
      test "false for discussion author without verified email address" do
        discussion = create(:discussion, :question, repository: @repo)
        comment = create(:discussion_comment, repository: @repo, discussion: discussion)
        discussion.user.emails.map(&:unverify!)

        refute comment.can_mark_as_answer?(discussion.user)
        refute comment.async_can_mark_as_answer?(discussion.user).sync
      end

      test "false for maintainer without verified email address" do
        @org_repo.add_member(@unverified, action: :maintain)

        refute @org_comment.can_mark_as_answer?(@unverified)
        refute @org_comment.async_can_mark_as_answer?(@unverified).sync
      end
    else
      test "true for discussion author without verified email address" do
        discussion = create(:discussion, :question, repository: @repo)
        comment = create(:discussion_comment, repository: @repo, discussion: discussion)
        discussion.user.emails.map(&:unverify!)

        assert comment.can_mark_as_answer?(discussion.user)
        assert comment.async_can_mark_as_answer?(discussion.user).sync
      end

      test "true for maintainer without verified email address" do
        @org_repo.add_member(@unverified, action: :maintain)

        assert @org_comment.can_mark_as_answer?(@unverified)
        assert @org_comment.async_can_mark_as_answer?(@unverified).sync
      end
    end

    test "false when setting disabled" do
      @org_repo.turn_off_discussions(actor: @admin, instrument: false)

      refute @org_comment.can_mark_as_answer?(@admin)
      refute @org_comment.async_can_mark_as_answer?(@admin).sync
    end

    test "false for archived repo" do
      @repo.set_archived

      refute @comment.can_mark_as_answer?(@owner)
      refute @comment.async_can_mark_as_answer?(@owner).sync
    end
  end

  context "unmarking a comment as the answer" do
    test "false for author of comment" do
      refute_comment_can_be_unmarked_as_answer(@answer, user: @answer.user)
    end

    test "false for comment that's not the answer" do
      refute_comment_can_be_unmarked_as_answer(@comment, user: @owner)
    end

    if GitHub.email_verification_enabled?
      test "false for answer when user doesn't have a verified email address" do
        unverified = create(:user)
        @org_repo.add_member(unverified, action: :maintain)
        refute_comment_can_be_unmarked_as_answer(@org_answer, user: unverified)
      end

      test "false for discussion author without verified email address" do
        discussion = create(:discussion, repository: @repo)
        answer = create(:discussion_comment, repository: @repo, discussion: discussion,
          body: "This is the best answer.")
        discussion.chosen_comment = answer
        discussion.save!
        discussion.user.emails.map(&:unverify!)

        refute_comment_can_be_unmarked_as_answer(answer, user: discussion.user)
      end
    else
      test "true for answer when user doesn't have a verified email address" do
        unverified = create(:user)
        @org_repo.add_member(unverified, action: :maintain)
        assert_comment_can_be_unmarked_as_answer(@org_answer, user: unverified)
      end

      test "true for discussion author without verified email address" do
        discussion = create(:discussion, :question, repository: @repo)
        answer = create(:discussion_comment, repository: @repo, discussion: discussion,
          body: "This is the best answer.")
        discussion.chosen_comment = answer
        discussion.save!
        discussion.user.emails.map(&:unverify!)

        assert_comment_can_be_unmarked_as_answer(answer, user: discussion.user)
      end
    end

    test "requires triage+" do
      @matrix.each_subject { |comment| comment.mark_as_answer(actor: comment.repository.owner) }

      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_can_be_unmarked_as_answer(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_can_be_unmarked_as_answer(comment, user: user) },
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when setting is disabled" do
      @org_repo.turn_off_discussions(actor: @admin, instrument: false)
      refute_comment_can_be_unmarked_as_answer(@org_answer, user: @admin)
    end

    test "true for discussion author who can see the repo" do
      assert_comment_can_be_unmarked_as_answer(@answer, user: @answered_discussion.user)
    end

    test "false for discussion author who cannot see the repo" do
      @private_discussion.chosen_comment = @private_comment
      @private_discussion.save!

      assert_comment_can_be_unmarked_as_answer(@private_comment.reload, user: @private_author)

      @private_repo.remove_member(@private_author)

      refute_comment_can_be_unmarked_as_answer(@private_comment, user: @private_author)
    end

    test "false for archived repo" do
      @repo.set_archived
      refute_comment_can_be_unmarked_as_answer(@answer, user: @owner)
    end
  end

  context "#answer? and #async_answer?" do
    test "true for a chosen comment" do
      assert_predicate @answer, :answer?
      assert @answer.async_answer?.sync
    end

    test "false for a non-chosen comment" do
      refute_predicate @comment, :answer?
      refute @comment.async_answer?.sync
    end

    test "false for a chosen comment in a discussion that does not support answers" do
      @answer.discussion.category.update!(supports_mark_as_answer: false)

      refute_predicate @answer, :answer?
      refute @answer.async_answer?.sync
    end

    test "true for a child comment" do
      # Contrived example, so skip validations
      @answer.update_column(:parent_comment_id, @comment.id)

      assert_predicate @answer, :answer?
      assert @answer.async_answer?.sync
    end
  end

  context "delete comment permissions" do
    test "true for author of comment with read+" do
      assert_block = ->(comment, user) do
        comment.update!(user: user)
        assert_comment_deletable(comment, user: user)
      end

      refute_block = ->(comment, user) do
        comment.update!(user: user)
        refute_comment_deletable(comment, user: user)
      end

      @matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when comment has already been wiped" do
      assert @parent_comment.wipe_or_destroy(@parent_comment.user)
      assert_predicate @parent_comment, :wiped?

      refute_comment_deletable(@parent_comment, user: @owner)
    end

    if GitHub.email_verification_enabled?
      test "returns false for user who doesn't have verified email address" do
        write_user = create(:user)
        @repo.add_member(write_user, action: :write)

        refute_comment_deletable(@comment, user: write_user)
      end
    else
      test "returns true for user who doesn't have verified email address" do
        write_user = create(:user)
        @repo.add_member(write_user, action: :write)

        assert_comment_deletable(@comment, user: write_user)
      end
    end

    test "requires triage+" do
      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_deletable(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_deletable(comment, user: user) },
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when repository does not have discussions turned on" do
      @org_repo.turn_off_discussions(actor: @admin, instrument: false)

      refute_comment_deletable(@org_comment.reload, user: @admin)
    end

    test "false when org-owned repository is archived" do
      @org_repo.set_archived

      refute_comment_deletable(@org_comment.reload, user: @admin)
    end

    test "false when user-owned repository is archived" do
      @repo.set_archived

      refute_comment_deletable(@comment.reload, user: @owner)
    end

    test "false for author of comment when discussion is locked" do
      @comment.discussion.stubs(:locked?).returns(true)

      refute_comment_deletable(@comment, user: @comment.user)
    end

    test "requires triage+ when discussion is locked" do
      @matrix.each_subject { |comment| comment.discussion.stubs(:locked?).returns(true) }

      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_deletable(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_deletable(comment, user: user) },
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "integrations require an installation with discussions: write permission" do
      @matrix.bot_scenarios_custom(
        assert_block: ->(comment, bot) { assert_comment_deletable(comment, user: bot) },
        refute_block: ->(comment, bot) { refute_comment_deletable(comment, user: bot) },
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for an integration on a wiped comment" do
      @parent_comment.wipe_or_destroy(@owner)

      refute_comment_deletable(@parent_comment.reload, user: @bot_owner_write)
    end

    test "false for an integration when the repo has turned off discussions" do
      @repo.turn_off_discussions(actor: @owner, instrument: false)

      refute_comment_deletable(@comment.reload, user: @bot_owner_write)
    end

    test "false for an integration when the repo is locked" do
      @repo.lock_for_migration

      refute_comment_deletable(@comment.reload, user: @bot_owner_write)
    end

    test "false for an integration when the repo is archived" do
      @repo.set_archived

      refute_comment_deletable(@comment.reload, user: @bot_owner_write)
    end
  end

  context "#can_toggle_minimized_discussion_comment?" do
    test "requires triage+" do
      allowed = ->(comment, user) do
        assert DiscussionComment.can_toggle_minimized_discussion_comment?(comment.discussion, actor: user)
      end
      denied = ->(comment, user) do
        refute DiscussionComment.can_toggle_minimized_discussion_comment?(comment.discussion, actor: user)
      end

      @matrix.user_scenarios_custom(
        assert_block: allowed,
        refute_block: denied,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false for author of comment" do
      refute DiscussionComment.can_toggle_minimized_discussion_comment?(@unanswered_discussion,
        actor: @comment.user)
    end

    if GitHub.email_verification_enabled?
      test "false for user without a verified email address" do
        @repo.add_member(@unverified, action: :write)
        refute DiscussionComment.can_toggle_minimized_discussion_comment?(@unanswered_discussion,
          actor: @unverified)
      end
    else
      test "true for user without a verified email address" do
        @repo.add_member(@unverified, action: :write)
        assert DiscussionComment.can_toggle_minimized_discussion_comment?(@unanswered_discussion,
          actor: @unverified)
      end
    end

    test "false for site admins that don't have write access to the repo" do
      site_admin = create(:staff_admin_user, :verified)
      refute DiscussionComment.can_toggle_minimized_discussion_comment?(@unanswered_discussion,
        actor: site_admin)
    end
  end

  context "#async_minimizable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(:async_minimizable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false for author of comment" do
      refute @comment.async_minimizable_by?(@comment.user).sync
    end

    test "true for site admins even if they don't have write access to the repo" do
      site_admin = create(:staff_admin_user, :verified)
      assert @comment.async_minimizable_by?(site_admin).sync
    end

    if GitHub.organization_moderators_enabled?
      test "returns true for organization moderator" do
        moderator = create(:verified_user)
        @org.add_member(moderator)
        @org.moderation.add_moderator(moderator, actor: @org.admin)
        assert @org.moderator?(moderator)
        assert @org_comment.async_minimizable_by?(moderator).sync
      end

      test "returns true for organization moderator via team" do
        team = create(:public_team, organization: @org)
        moderator = create(:verified_user)
        @org.add_member(moderator)
        team.add_member(moderator)
        @org.moderation.add_moderator(team, actor: @org.admin)
        assert @org.moderator?(moderator)
        assert @org_comment.async_minimizable_by?(moderator).sync
      end

      test "returns false for organization moderator in private repo" do
        @org_repo.update!(public: false)
        assert_predicate @org_repo, :private?
        team = create(:public_team, organization: @org)
        moderator = create(:verified_user)
        @org.add_member(moderator)
        team.add_member(moderator)
        @org.moderation.add_moderator(team, actor: @org.admin)
        assert @org.moderator?(moderator)
        refute @org_comment.async_minimizable_by?(moderator).sync
      end
    end
  end

  context "#async_locked_for?" do
    test "true when its discussion is locked and user lacks repo write access" do
      Discussion.any_instance.stubs(:locked?).returns(true)
      assert @comment.async_locked_for?(@rando).sync
    end

    test "false when its discussion is locked and user has repo write access" do
      Discussion.any_instance.stubs(:locked?).returns(true)
      refute @comment.async_locked_for?(@owner).sync
    end

    test "true when discussion is locked with reactions allowed" do
      @unanswered_discussion.lock(actor: @owner, allow_reactions: true)
      assert @comment.async_locked_for?(@rando).sync
    end

    test "false when its discussion is not locked" do
      refute @comment.async_locked_for?(@rando).sync
    end
  end

  context "#async_reactions_locked_for?" do
    test "true when its discussion is locked and user lacks repo write access" do
      @comment.discussion.lock(actor: @owner, allow_reactions: false)
      assert @comment.async_reactions_locked_for?(@rando).sync
    end

    test "false when its discussion is locked and user has repo write access" do
      @comment.discussion.lock(actor: @owner, allow_reactions: false)
      refute @comment.async_reactions_locked_for?(@owner).sync
    end

    test "false when its discussion is locked with reactions allowed and user does not have repo write access" do
      @comment.discussion.lock(actor: @owner, allow_reactions: true)
      refute @comment.async_reactions_locked_for?(@rando).sync
    end

    test "false when discussion is unlocked" do
      refute @comment.async_reactions_locked_for?(@rando).sync
    end
  end

  test "deleting chosen comment unmarks it as answer" do
    assert_predicate @answered_discussion, :answered?

    @answer.actor = @answer.user

    assert_difference("DiscussionComment.count", -1) do
      assert @answer.destroy
    end

    refute_predicate @answered_discussion.reload, :answered?
  end

  test "deleting a chosen comment also deletes the associated events" do
    assert_predicate @answered_discussion, :answered?

    @answer.mark_as_answer

    assert_difference("DiscussionEvent.answer_marked.count", -1) do
      assert_difference("DiscussionComment.count", -1) do
        assert @answer.destroy
      end
    end
  end

  context "whether user can react to comment" do
    test "requires read+" do
      @matrix.user_scenarios_custom(
        assert_block: ->(comment, user) { assert_comment_reactable(comment, user: user) },
        refute_block: ->(comment, user) { refute_comment_reactable(comment, user: user) },
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    if GitHub.email_verification_enabled?
      test "false when user lacks verified email address" do
        refute_comment_reactable(@comment, user: @unverified)
      end
    else
      test "true when user lacks verified email address" do
        assert_comment_reactable(@comment, user: @unverified)
      end
    end

    test "false when user has been blocked by discussion author" do
      @unanswered_discussion.user.block(@rando)

      refute_comment_reactable(@comment, user: @rando)
    end

    test "false when user has been blocked by repository owner" do
      @owner.block(@rando)

      refute_comment_reactable(@comment, user: @rando)
    end

    test "false when discussion has been locked" do
      @unanswered_discussion.lock(actor: @owner)

      refute_comment_reactable(@comment, user: @rando)
    end

    test "true for an admin when the discussion is locked" do
      @unanswered_discussion.lock(actor: @owner)

      assert_comment_reactable(@comment, user: @owner)
    end

    test "false when discussion comment has been wiped" do
      assert @parent_comment.wipe_or_destroy(@parent_comment.user),
        "need a wiped comment for this test"

      refute_comment_reactable(@parent_comment, user: @rando)
    end
  end

  context "#reportable_by_comment_id" do
    test "false for all comments on Enterprise" do
      result = DiscussionComment.reportable_by_comment_id(@unanswered_discussion,
        actor: @owner)

      refute_nil result
      refute result[@comment.id]
    end if GitHub.enterprise?

    test "false for comments when repository is private", skip_enterprise: true do
      result = DiscussionComment.reportable_by_comment_id(@private_discussion, actor: @owner)

      refute_nil result
      refute result[@private_comment.id]
    end

    test "false for comments for anonymous user", skip_enterprise: true do
      result = DiscussionComment.reportable_by_comment_id(@unanswered_discussion, actor: nil)

      refute_nil result
      refute result[@comment.id]
    end

    test "true for comments for user with repo write access", skip_enterprise: true do
      result = DiscussionComment.reportable_by_comment_id(@org_discussion, actor: @writer)

      refute_nil result
      assert result[@org_comment.id]
    end
  end

  context "#reportable_to_maintainer_by_comment_id" do
    test "false for all comments on Enterprise" do
      @org_repo.enable_tiered_reporting(actor: @org_admin)

      result = DiscussionComment.reportable_to_maintainer_by_comment_id(@org_discussion, actor: @triager_via_team)

      refute_nil result
      refute result[@org_comment.id]
    end if GitHub.enterprise?

    test "false for comments when repository is private", skip_enterprise: true do
      result = DiscussionComment.reportable_to_maintainer_by_comment_id(@org_discussion, actor: @org_admin)

      refute_nil result
      refute result[@private_comment.id]
    end

    test "false for comments for anonymous user", skip_enterprise: true do
      @org_repo.enable_tiered_reporting(actor: @org_admin)

      result = DiscussionComment.reportable_to_maintainer_by_comment_id(@org_discussion, actor: nil)

      refute_nil result
      refute result[@org_comment.id]
    end

    test "true for comments for user with repo read access when feature enabled", skip_enterprise: true do
      # Users with write access will be able to moderate comment, so they don't need
      # to report directly to maintainers
      @org_repo.enable_tiered_reporting(actor: @org_admin)

      result = DiscussionComment.reportable_to_maintainer_by_comment_id(@org_discussion, actor: @reader)

      refute_nil result
      assert result[@org_comment.id]
    end
  end

  context "#disallow_marking_as_answer_reason and #marking_as_answer_allowed?" do
    test "allowed for comments that can be marked" do
      assert_nil @comment.disallow_marking_as_answer_reason
      assert_predicate @comment, :marking_as_answer_allowed?
    end

    test "disallowed if the discussion is being deleted" do
      # Use delete instead of destroy to prevent callbacks from deleting the comment
      @unanswered_discussion.delete

      assert_equal :discussion_deleting, @comment.disallow_marking_as_answer_reason
      refute_predicate @comment, :marking_as_answer_allowed?
    end

    test "disallowed if the discussion is already answered" do
      assert_equal :already_answered, @nonanswer.disallow_marking_as_answer_reason
      refute_predicate @nonanswer, :marking_as_answer_allowed?
    end

    test "disallowed if the discussion is already answered by this comment" do
      assert_equal :already_marked, @answer.disallow_marking_as_answer_reason
      refute_predicate @answer, :marking_as_answer_allowed?
    end

    test "disallowed if the discussion category does not support answers" do
      @unanswered_discussion.category.update!(supports_mark_as_answer: false)

      assert_equal :unsupported_category, @comment.disallow_marking_as_answer_reason
      refute_predicate @comment, :marking_as_answer_allowed?
    end

    test "disallowed if the comment has been wiped" do
      @parent_comment.wipe_or_destroy(@owner)

      assert_equal :wiped, @parent_comment.disallow_marking_as_answer_reason
      refute_predicate @parent_comment, :marking_as_answer_allowed?
    end

    test "disallowed if the comment has been minimized" do
      @comment.set_minimized(@owner, "quite rude", "OFF_TOPIC", @comment.user)

      assert_equal :minimized, @comment.disallow_marking_as_answer_reason
      refute_predicate @comment, :marking_as_answer_allowed?
    end

    test "allowed for child comments" do
      assert_nil @child_comment.disallow_marking_as_answer_reason
      assert_predicate @child_comment, :marking_as_answer_allowed?
    end
  end

  context "#mark_as_answer" do
    test "updates conversation with answer" do
      @comment.mark_as_answer(actor: @owner)
      assert_equal @comment, @comment.discussion.chosen_comment
      assert @comment.reload.answer?
    end

    test "creates a discussion event" do
      assert_difference("DiscussionEvent.count") do
        @comment.mark_as_answer(actor: @comment.discussion.user)
      end

      last_event = DiscussionEvent.for_discussion(@comment.discussion).
        by_actor(@comment.discussion.user).
        for_repository(@comment.repository).
        for_comment(@comment).last
      refute_nil last_event
    end

    test "returns false if discussion missing" do
      @comment.discussion.delete
      refute @comment.reload.mark_as_answer(actor: @owner)
    end

    test "updates conversation with child comment answer" do
      @child_comment.mark_as_answer(actor: @owner)
      assert_equal @child_comment, @child_comment.discussion.chosen_comment
      assert @child_comment.reload.answer?
    end
  end

  context "#disallow_unmarking_as_answer_reason and #unmarking_as_answer_allowed?" do
    test "allowed for comments that can be unmarked" do
      assert_nil @answer.disallow_unmarking_as_answer_reason
      assert_predicate @answer, :unmarking_as_answer_allowed?
    end

    test "disallowed for comments that are not marked as an answer" do
      assert_equal :already_unmarked, @nonanswer.disallow_unmarking_as_answer_reason
      refute_predicate @nonanswer, :unmarking_as_answer_allowed?
    end

    test "disallowed if discussion category does not support answers" do
      @answered_discussion.category.update!(supports_mark_as_answer: false)

      assert_equal :unsupported_category, @answer.disallow_unmarking_as_answer_reason
      refute_predicate @answer, :unmarking_as_answer_allowed?
    end

    test "disallowed if its discussion is being deleted" do
      # Use delete instead of destroy to prevent callbacks from deleting the comment
      @answered_discussion.delete

      assert_equal :discussion_deleting, @nonanswer.disallow_unmarking_as_answer_reason
      refute_predicate @nonanswer, :unmarking_as_answer_allowed?
    end
  end

  context "#unmark_as_answer" do
    test "updates the conversation with no answer" do
      @answer.unmark_as_answer(actor: @owner)
      assert_nil @answer.discussion.chosen_comment
      refute @answer.reload.answer?
    end

    test "creates a discussion event" do
      assert_difference("DiscussionEvent.count") do
        @answer.unmark_as_answer(actor: @answer.discussion.user)
      end

      last_event = DiscussionEvent.for_discussion(@answer.discussion).
        by_actor(@answer.discussion.user).
        for_repository(@answer.repository).
        for_comment(@answer).last
      refute_nil last_event
    end

    test "returns false if discussion missing" do
      @answer.discussion.delete
      refute @answer.reload.unmark_as_answer(actor: @owner)
    end

    test "returns false when comment is not the answer" do
      refute @comment.unmark_as_answer(actor: @owner)
    end
  end

  context "#blockable_by_comment_id" do
    test "false for comments in a user-owned repository" do
      result = DiscussionComment.blockable_by_comment_id(@unanswered_discussion, actor: @owner)

      refute_nil result
      refute result[@comment.id]
    end

    test "true for comments in an org-owned repo for org admins" do
      result = DiscussionComment.blockable_by_comment_id(@org_discussion, actor: @org_admin)

      refute_nil result
      assert result[@org_comment.id]
    end
  end

  context "not_minimized scope" do
    test "includes comments that haven't been hidden" do
      hidden_comment = create(:discussion_comment, :minimized, discussion: @unanswered_discussion, repository: @repo)
      visible_comment = create(:discussion_comment, discussion: @unanswered_discussion, repository: @repo)

      result = @unanswered_discussion.comments.not_minimized

      refute_includes result, hidden_comment
      assert_includes result, visible_comment
    end
  end

  context "#unblockable_by_comment_id" do
    test "false for comments in a user-owned repository" do
      result = DiscussionComment.unblockable_by_comment_id(@unanswered_discussion, actor: @owner)

      refute_nil result
      refute result[@comment.id]
    end

    test "true for comments in an org-owned repo for org admins when comment author has been blocked" do
      @org.block(@org_comment.user)
      comment_with_not_blocked_author = create(:discussion_comment, discussion: @org_discussion)

      result = DiscussionComment.unblockable_by_comment_id(@org_discussion, actor: @org_admin)

      refute_nil result
      assert result[@org_comment.id]
      refute result[comment_with_not_blocked_author.id]
    end
  end

  context "#author" do
    test "returns the user if they exist" do
      comment = build(:discussion_comment, user: @owner)
      assert_equal @owner, comment.author
    end

    test "returns the ghost user if the original user is gone" do
      @comment.user = nil
      refute_nil @comment.author
      assert_equal User.ghost, @comment.author
    end
  end

  context "#authored_by_ghost?" do
    test "true when user does not exist" do
      @comment.user = nil
      assert_predicate @comment, :authored_by_ghost?
    end

    test "false when user exists" do
      refute_nil @comment.user
      refute_predicate @comment, :authored_by_ghost?
    end
  end

  context "#latest_edit_by_comment_id" do
    test "returns latest content edit for comments by ID" do
      oldest_edit = Timecop.freeze(1.year.ago) do
        create(:discussion_comment_edit, discussion_comment: @comment)
      end
      latest_edit = Timecop.freeze(1.week.ago) do
        create(:discussion_comment_edit, discussion_comment: @comment)
      end

      result = DiscussionComment.latest_edit_by_comment_id(@unanswered_discussion,
        actor: @unanswered_discussion.user)

      refute_nil result
      assert_equal latest_edit, result[@comment.id]
    end
  end

  context "#report_count_by_comment_id" do
    test "returns report count for comments by ID" do
      other_comment = create(:discussion_comment, discussion: @unanswered_discussion)
      create(:abuse_report, reported_content: other_comment)

      result = DiscussionComment.report_count_by_comment_id(@unanswered_discussion,
        actor: @staff)

      refute_nil result
      assert_equal 0, result[@comment.id]
      assert_equal 1, result[other_comment.id]
    end

    test "returns 0 when viewer cannot see reports" do
      create(:abuse_report, reported_content: @comment)
      refute_predicate @unanswered_discussion.user, :site_admin?

      result = DiscussionComment.report_count_by_comment_id(@unanswered_discussion,
        actor: @unanswered_discussion.user)

      refute_nil result
      assert_equal 0, result[@comment.id]
    end
  end

  context "#last_reported_at_by_comment_id" do
    test "returns latest report time for comments by ID" do
      other_comment = create(:discussion_comment, discussion: @unanswered_discussion)
      report = create(:abuse_report, reported_content: other_comment)

      result = DiscussionComment.last_reported_at_by_comment_id(@unanswered_discussion,
        actor: @staff)

      refute_nil result
      assert_nil result[@comment.id]
      assert_equal report.created_at, result[other_comment.id]
    end

    test "returns nil when viewer cannot see reports" do
      create(:abuse_report, reported_content: @comment)
      refute_predicate @unanswered_discussion.user, :site_admin?

      result = DiscussionComment.last_reported_at_by_comment_id(@unanswered_discussion,
        actor: @unanswered_discussion.user)

      refute_nil result
      assert_nil result[@comment.id]
    end
  end

  context "#top_report_reason_by_comment_id" do
    test "returns top report reason for comments by ID" do
      other_comment = create(:discussion_comment, discussion: @unanswered_discussion)
      create(:abuse_report, reported_content: other_comment)

      result = DiscussionComment.top_report_reason_by_comment_id(@unanswered_discussion,
        actor: @staff)

      refute_nil result
      assert_nil result[@comment.id]
      assert_equal "unspecified", result[other_comment.id]
    end

    test "returns nil when viewer cannot see reports" do
      create(:abuse_report, reported_content: @comment)
      refute_predicate @unanswered_discussion.user, :site_admin?

      result = DiscussionComment.top_report_reason_by_comment_id(@unanswered_discussion,
        actor: @unanswered_discussion.user)

      refute_nil result
      assert_nil result[@comment.id]
    end
  end

  context "#async_path_uri" do
    test "generates the path URI of the comment" do
      assert_equal "/#{@repo.nwo}/discussions/#{@unanswered_discussion.number}#discussioncomment-#{@comment.id}",
        @comment.async_path_uri.sync.to_s
    end

    test "handles a deleted discussion" do
      DiscussionDeleter.new(@unanswered_discussion).delete(@rando)

      assert_equal "/#{@repo.nwo}/discussions/#{@unanswered_discussion.number}#discussioncomment-#{@comment.id}",
        @comment.async_path_uri.sync.to_s
    end

    test "handles a discussion deleted without a DeletedDiscussion" do
      # Oops someone tripped over the power cord
      @unanswered_discussion.delete

      assert_equal "/#{@repo.nwo}/discussions", @comment.async_path_uri.sync.to_s
    end
  end

  context "#top_level_comment?" do
    test "true when no parent comment" do
      assert_nil @answer.parent_comment
      assert_predicate @answer, :top_level_comment?
    end

    test "false when there is a parent comment" do
      refute_nil @child_comment.parent_comment
      refute_predicate @child_comment, :top_level_comment?
    end
  end

  context "#nested?" do
    test "false when no parent comment" do
      assert_nil @answer.parent_comment
      refute_predicate @answer, :nested?
    end

    test "true when there is a parent comment" do
      refute_nil @child_comment.parent_comment
      assert_predicate @child_comment, :nested?
    end
  end

  context "#upvote" do
    test "creates new vote when user hasn't voted already" do
      user = create(:verified_user)

      assert_difference("@comment.votes.for_user(user).count") do
        assert @comment.upvote(user)
      end
    end

    test "does not create new vote when user has voted already" do
      user = create(:verified_user)
      create(:discussion_comment_vote, discussion: @comment.discussion, comment: @comment,
        user: user)

      assert_no_difference("DiscussionVote.count") do
        assert @comment.upvote(user)
      end
    end

    test "triggers websocket notification" do
      freeze_time do
        GitHub::WebSocket.expects(:notify_discussion_channel).with(
          @comment.discussion,
          GitHub::WebSocket::Channels.discussion(@comment.discussion),
          timestamp: Time.now.to_i,
          wait: @comment.default_live_updates_wait,
          reason: "discussion comment ##{@comment.id} updated",
          gid: @comment.global_relay_id,
        )

        user = create(:verified_user)
        @comment.upvote(user)
      end
    end
  end

  context "#vote_by" do
    test "returns existing vote for given user" do
      user = create(:verified_user)
      vote = create(:discussion_comment_vote, discussion: @comment.discussion, comment: @comment,
        user: user)

      assert_equal vote, @comment.vote_by(user, upvote: true)
    end

    test "returns nil when given user has not voted on the comment" do
      user = create(:verified_user)

      assert_nil @comment.vote_by(user, upvote: true)
    end
  end

  context "#detect_comment_language" do
    test "does not queue job on Enterprise" do
      assert_no_enqueued_jobs only: DetectCommentLanguageJob do
        @comment.update_body(Faker::Lorem.sentence, @comment.user)
      end
    end if GitHub.enterprise?

    test "does not queue job to detect language when other attribute is updated", skip_enterprise: true do
      assert_no_enqueued_jobs only: DetectCommentLanguageJob do
        @comment.upvote(@owner)
      end
    end

    test "enqueues job to detect language when the discussion comment is created", skip_enterprise: true do
      comment = create(:discussion_comment, discussion: @unanswered_discussion)

      DetectCommentLanguageJob.expects(:enqueue_once_per_interval)
        .with(
          has_entries(
            args: [comment.id, "DiscussionComment"],
            unique_id: "DiscussionComment:#{comment.id}",
            interval: 10.minutes,
            run_at_beginning_of_interval: true
          )
        )

      comment.run_callbacks(:commit)
    end

    test "queues job to detect language when the discussion body is updated", skip_enterprise: true do
      assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
        @comment.update_body(Faker::Lorem.sentence, @comment.user)
      end
    end

    test "uses enqueue_once_per_interval when the discussion body is updated", skip_enterprise: true do
      DetectCommentLanguageJob.expects(:enqueue_once_per_interval)
        .with(
          has_entries(
            args: [@comment.id, "DiscussionComment"],
            unique_id: regexp_matches(/^DiscussionComment:#{@comment.id}:\d+$/),
            interval: 10.minutes,
            run_at_beginning_of_interval: true
          )
        )

      @comment.update_body(Faker::Lorem.sentence, @comment.user)
    end

    test "enqueues job only once in 10 minutes interval if discussion body is updated multiple times", skip_enterprise: true do
      Timecop.freeze do
        assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
          @comment.update_body(Faker::Lorem.sentence, @comment.user)
          @comment.detect_comment_language
        end
        Timecop.travel(11.minutes.from_now) do
          assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
            @comment.update_body(Faker::Lorem.sentence, @comment.user)
            @comment.detect_comment_language
          end
        end
      end
    end

    test "enqueues multiple jobs within interval if body changed", skip_enterprise: true do
      assert_enqueued_jobs 2, only: DetectCommentLanguageJob do
        @comment.update_body(Faker::Lorem.sentence, @comment.user)
        @comment.update_body(Faker::Lorem.sentence, @comment.user)
      end
    end
  end

  context "validations" do
    test "requires discussion" do
      comment = DiscussionComment.new
      refute_predicate comment, :valid?
      assert_includes comment.errors[:discussion], "must exist"
    end

    test "requires body on create" do
      comment = DiscussionComment.new
      refute_predicate comment, :valid?
      assert_includes comment.errors[:body], "can't be blank"
    end

    test "body cannot be too long" do
      expected_characters = 65536
      body = "a" * (MYSQL_UNICODE_BLOB_LIMIT + 1)
      comment = build(:discussion_comment)

      comment.body = body

      refute_predicate comment, :valid?, "#{comment.errors.full_messages}"
      assert_equal comment.errors.full_messages.first, "Body is too long (maximum is #{expected_characters} characters)"
    end

    test "allows blank body on update when deleted_at is set" do
      @comment.body = ""
      refute_predicate @comment, :valid?
      assert_includes @comment.errors[:body], "can't be blank"

      @comment.deleted_at = Time.now
      assert_predicate @comment, :valid?
    end

    test "requires a user at creation for comment in an 'open' discussion" do
      comment = build(:discussion_comment, user: nil)
      refute_predicate comment, :valid?
      assert_includes comment.errors[:user], "can't be blank"
    end

    test "does not require a user at creation for comment in a 'converting' discussion" do
      issue = create(:issue, repository: @repo)
      converting_discussion = Discussion.from_issue(issue, category: @repo.discussion_categories.last)
      converting_discussion.save!
      comment = build(:discussion_comment, discussion: converting_discussion, user: nil)

      assert_predicate comment, :valid?
    end

    test "does not require a user on update" do
      comment = create(:discussion_comment)
      refute_nil comment.user
      comment.user = nil
      assert comment.save
      assert_nil comment.reload.user
    end

    test "allows a comment replying to a comment in the same discussion" do
      parent_comment = @comment
      child_comment = build(:discussion_comment, discussion: @unanswered_discussion, parent_comment: parent_comment)
      assert_predicate child_comment, :valid?
    end

    test "disallows a comment replying to itself" do
      @comment.parent_comment = @comment
      refute_predicate @comment, :valid?
      assert_includes @comment.errors[:parent_comment], "cannot be itself"
    end

    test "disallows a comment replying to a comment that is a reply to a comment" do
      parent_comment = @comment
      child_comment = create(:discussion_comment, discussion: @unanswered_discussion, parent_comment: parent_comment)
      grandchild_comment = build(:discussion_comment, discussion: @unanswered_discussion, parent_comment: child_comment)
      refute_predicate grandchild_comment, :valid?
      assert_includes grandchild_comment.errors[:parent_comment], "is already in a thread, cannot reply to it"
    end

    test "disallows replying to a comment that is in a different discussion" do
      parent_comment = @comment
      child_comment = build(:discussion_comment, discussion: @org_discussion, parent_comment: parent_comment)
      refute_predicate child_comment, :valid?
      assert_includes child_comment.errors[:parent_comment], "is in a different discussion"
    end

    test "requires parent comment to exist if ID is specified" do
      child_comment = build(:discussion_comment, parent_comment_id: -1)
      refute_predicate child_comment, :valid?
      assert_includes child_comment.errors[:parent_comment], "does not exist"
    end

    test "requires non-minimized parent comment" do
      hidden_comment = create(:discussion_comment, comment_hidden: true, discussion: @unanswered_discussion)
      child_comment = build(:discussion_comment, parent_comment: hidden_comment, discussion: @unanswered_discussion)
      refute_predicate child_comment, :valid?
      assert_includes child_comment.errors[:parent_comment], "has been hidden and cannot be replied to"
    end

    test "requires a repository" do
      comment = DiscussionComment.new
      refute_predicate comment, :valid?
      assert_includes comment.errors[:repository], "must exist"
    end

    if GitHub.email_verification_enabled?
      test "requires user to have a verified email address at creation" do
        unverified_user = create(:user)
        comment = build(:discussion_comment, user: unverified_user)
        refute_predicate comment, :valid?
        assert_includes comment.errors[:user], "must have a verified email address"
      end
    else
      test "does not require user to have a verified email address at creation" do
        unverified_user = create(:user)
        comment = build(:discussion_comment, user: unverified_user)
        assert_predicate comment, :valid?
      end
    end

    test "does not require user to have a verified email address on update" do
      @comment.user = create(:user)
      assert_predicate @comment, :valid?
    end

    test "does not require user to have verified email address at creation if converting from issue comment" do
      discussion = create(:discussion, state: :converting, issue: create(:issue))
      unverified_user = create(:user)
      comment = build(:discussion_comment, user: unverified_user, discussion: discussion)
      assert_predicate comment, :valid?
    end

    test "does not require bot to have verified email address" do
      bot = make_integration_installation(target: @owner).bot
      comment = build(:discussion_comment, user: bot)
      assert_predicate comment, :valid?
    end

    test "validates that the repo owner has not blocked the comment author" do
      discussion = create(:discussion)
      repo_owner = discussion.repository.owner
      blocked_user = create(:verified_user)
      repo_owner.block(blocked_user)

      comment = build(:discussion_comment, user: blocked_user, discussion: discussion)
      refute_predicate comment, :valid?
      assert_includes comment.errors[:user], "cannot comment at this time"
    end

    test "validates on create that the discussion creator has not blocked the comment author" do
      discussion = create(:discussion)
      discussion_creator = discussion.user
      blocked_user = create(:verified_user)
      discussion_creator.block(blocked_user)

      comment = build(:discussion_comment, user: blocked_user, discussion: discussion)
      refute_predicate comment, :valid?
      assert_includes comment.errors[:user], "cannot comment at this time"
    end

    test "validates on update that the discussion creator has not blocked the comment author" do
      discussion = create(:discussion)
      discussion_creator = discussion.user
      user_to_be_blocked = create(:verified_user)
      comment = create(:discussion_comment, user: user_to_be_blocked, discussion: discussion)
      discussion_creator.block(user_to_be_blocked)

      refute comment.update_body("brand new body", user_to_be_blocked)

      refute_predicate comment, :valid?
      assert_includes comment.errors[:user], "cannot comment at this time"
    end

    test "validates that there's no blocked error when repo owner comments when blocked" do
      repo = create(:repository, owner: @rando, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      discussion_creator = discussion.user

      discussion_creator.block(@rando)

      comment = build(:discussion_comment, user: @rando, discussion: discussion)
      assert_predicate comment, :valid?
    end
  end

  context "update comment count" do
    test "updates discussion comment count on create" do
      discussion = create(:discussion)
      assert_equal 0, discussion.comment_count

      create(:discussion_comment, discussion: discussion)

      assert_equal 1, discussion.reload.comment_count
    end
  end

  context "when collaborator-only interaction limits are enabled" do
    test "non-collaborator cannot create a discussion comment" do
      interaction = RepositoryInteractionAbility.new(@org_repo)
      interaction.set_ability(:collaborators_only, @repo_admin)

      ex = assert_raises(ActiveRecord::RecordInvalid) do
        create :discussion_comment, user: @rando, discussion: @org_discussion
      end
      assert_equal "Validation failed: could not be created. Interactions on this repository have been restricted to collaborators only.",
        ex.message
    end

    test "collaborator can create a discussion comment" do
      interaction = RepositoryInteractionAbility.new(@org_repo)
      interaction.set_ability(:collaborators_only, @repo_admin)

      discussion_comment = create :discussion_comment, discussion: @org_discussion, user: @writer
      assert_predicate discussion_comment, :valid?
    end

    test "non-collaborator cannot edit their discussion comment" do
      interaction = RepositoryInteractionAbility.new(@org_repo)
      interaction.set_ability(:collaborators_only, @repo_admin)

      refute @org_comment.update_body("Brand new body", @org_comment.user)

      assert_includes @org_comment.errors[:base],
        "could not be created. Interactions on this repository have been restricted to collaborators only."
    end

    test "collaborator can edit the non-collaborator's discussion comment" do
      interaction = RepositoryInteractionAbility.new(@org_repo)
      interaction.set_ability(:collaborators_only, @repo_admin)

      assert @org_comment.update_body("Brand new body", @writer)

      assert_empty @org_comment.errors[:base]
    end
  end if GitHub.interaction_limits_enabled?

  context "rate limits" do
    test "returns false when rate limit is exceeded" do
      enable_content_creation_rate_limiting
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              @org_discussion.comments.create(body: "??", user: @org_discussion.user)
            end

            comment = @org_discussion.comments.new(body: "??", user: @org_discussion.user)

            refute comment.save
            assert_equal expected_errors, comment.errors.full_messages
          end
        end
      end
    end
  end

  context "deletion" do
    test "updates discussion comment count on delete" do
      comment = create(:discussion_comment)
      assert_equal 1, comment.discussion.comment_count

      comment.destroy!

      assert_equal 0, comment.discussion.reload.comment_count
    end

    test "unmarks the comment as the chosen comment on deletion" do
      comment = create(:discussion_comment, :answer)
      comment.destroy!
      assert_nil comment.discussion.reload.chosen_comment_id
    end

    test "unmarks the comment as the chosen comment on deletion even if the category does not support Q&A" do
      comment = create(:discussion_comment, :answer)
      comment.discussion.category.update!(supports_mark_as_answer: false)
      comment.destroy!
      assert_nil comment.discussion.reload.chosen_comment_id
    end

    test "deletes parent comment when last child of a wiped parent is deleted" do
      parent_comment = create(:discussion_comment, :parent, discussion: @unanswered_discussion)
      assert parent_comment.wipe_or_destroy(parent_comment.user),
        "need parent comment to be wiped for this test"
      assert_equal 1, parent_comment.comment_count
      child_comment = parent_comment.comments.first

      assert_difference("DiscussionComment.count", -2) do
        assert child_comment.destroy
      end

      refute DiscussionComment.exists?(child_comment.id)
      refute DiscussionComment.exists?(parent_comment.id)
    end

    test "does not delete parent comment when child of a wiped parent is deleted if there are other child comments" do
      parent_comment = create(:discussion_comment, :parent, discussion: @unanswered_discussion)
      assert parent_comment.wipe_or_destroy(parent_comment.user),
        "need parent comment to be wiped for this test"
      child_comment = parent_comment.comments.first
      other_child_comment = create(:discussion_comment, discussion: @unanswered_discussion,
        parent_comment: parent_comment)
      assert_equal 2, parent_comment.comment_count

      assert_difference("DiscussionComment.count", -1) do
        assert child_comment.destroy
      end

      refute DiscussionComment.exists?(child_comment.id)
      assert DiscussionComment.exists?(parent_comment.id)
      assert DiscussionComment.exists?(other_child_comment.id)
    end

    test "does not delete parent comment when last child of a non-wiped parent is deleted" do
      parent_comment = create(:discussion_comment, :parent, discussion: @unanswered_discussion)
      assert_equal 1, parent_comment.comment_count
      child_comment = parent_comment.comments.first
      refute_predicate parent_comment, :wiped?,
        "need parent comment to not be wiped for this test"

      assert_difference("DiscussionComment.count", -1) do
        assert child_comment.destroy
      end

      refute DiscussionComment.exists?(child_comment.id)
      assert DiscussionComment.exists?(parent_comment.id)
    end
  end

  context "#wipe_or_destroy" do
    test "deletes record when it's not a parent comment" do
      assert_difference("DiscussionComment.count", -1) do
        assert @child_comment.wipe_or_destroy(@child_comment.user)
      end
      refute DiscussionComment.exists?(@child_comment.id)
    end

    test "empties body and sets deleted_at when it's a parent comment" do
      parent_comment = @child_comment.parent_comment
      Timecop.freeze do
        assert_no_difference("DiscussionComment.count") do
          assert parent_comment.wipe_or_destroy(parent_comment.user)
        end
        assert DiscussionComment.exists?(parent_comment.id)
        assert_equal "", parent_comment.reload.body
        assert_equal Time.zone.now.to_i, parent_comment.deleted_at.to_i
      end
      assert_equal parent_comment, @child_comment.reload.parent_comment
    end

    test "rolls back changes when some part of wiping a parent comment fails" do
      parent_comment = @child_comment.parent_comment
      @unanswered_discussion.update(chosen_comment_id: parent_comment.id)
      DiscussionComment.any_instance.stubs(:update).returns(false)

      assert_predicate @unanswered_discussion, :answered?
      assert_predicate parent_comment, :answer?,
        "parent comment must also be an answer for this test"

      assert_no_difference("DiscussionComment.count") do
        refute parent_comment.wipe_or_destroy(parent_comment.user)
      end

      assert_predicate @unanswered_discussion.reload, :answered?,
        "discussion should still be answered after rollback"
      assert_predicate parent_comment.reload, :answer?,
        "parent comment should still be the answer"
    end

    test "unmarks answer when wiping an answer" do
      parent_comment = @child_comment.parent_comment
      @unanswered_discussion.update(chosen_comment_id: parent_comment.id)

      assert_predicate @unanswered_discussion, :answered?
      assert_predicate parent_comment, :answer?,
        "parent comment must also be an answer for this test"

      assert_no_difference("DiscussionComment.count") do
        assert parent_comment.wipe_or_destroy(parent_comment.user)
      end

      refute_predicate @unanswered_discussion.reload, :answered?,
        "discussion should no longer be answered"
      refute_predicate parent_comment.reload, :answer?,
        "parent comment should no longer be marked as the answer"
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "logs event on creation" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        comment = create(:discussion_comment)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(comment),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          specimen_body: Hydro::EntitySerializer.specimen_data(comment.body),
          discussion: Hydro::EntitySerializer.discussion(comment.discussion),
          author: Hydro::EntitySerializer.user(comment.user),
          discussion_author: Hydro::EntitySerializer.user(comment.discussion.user),
          repository: Hydro::EntitySerializer.repository(comment.repository),
          repository_owner: Hydro::EntitySerializer.user(comment.repository.owner),
          feature_flags: []
        }

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: comment.repository.id,
          repository: Hydro::EntitySerializer.repository(comment.repository),
          repository_owner: Hydro::EntitySerializer.user(comment.repository.owner),
          discussion_id: comment.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(comment.discussion),
          discussion_comment_id: comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(comment),
          actor_id: comment.user.id,
          actor: Hydro::EntitySerializer.user(comment.user),
          action: :ACTION_COMMENT_CREATED,
          action_timestamp: Time.now,
          specimen_body: Hydro::EntitySerializer.specimen_data(comment.body)
        }

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentCreate")
          assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentCreate")
        end

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsComment")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsComment")
      end
    end

    test "DiscussionComment create publishes github.platform_health.v1.UserGeneratedContent" do
      reset_hydro
      comment = create(:discussion_comment)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :CREATE,
        content_type: :DISCUSSION_COMMENT,
        actor: Hydro::EntitySerializer.user(comment.author),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.discussions.v1.DiscussionCommentCreate"),
        content_database_id: comment.id,
        content_global_relay_id: comment.global_relay_id,
        content_created_at: comment.created_at,
        content_updated_at: comment.updated_at,
        content: Hydro::EntitySerializer.specimen_data(comment.body),
        parent_content_author: Hydro::EntitySerializer.user(comment.discussion.author),
        parent_content_database_id: comment.discussion.id,
        parent_content_global_relay_id: comment.discussion.global_relay_id,
        parent_content_created_at: comment.discussion.created_at,
        parent_content_updated_at: comment.discussion.updated_at,
        owner: Hydro::EntitySerializer.repository_owner(comment.discussion.repository),
        repository: Hydro::EntitySerializer.repository(comment.discussion.repository),
        content_visibility: :PUBLIC,
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "logs event on deletion" do
      travel_to Time.now do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @comment.actor = @owner

        @comment.destroy
        @unanswered_discussion.reload

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment),
          actor: Hydro::EntitySerializer.user(@owner),
          discussion: Hydro::EntitySerializer.discussion(@unanswered_discussion),
          author: Hydro::EntitySerializer.user(@comment.user),
          discussion_author: Hydro::EntitySerializer.user(@unanswered_discussion.user),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
        }

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @comment.repository.id,
          repository: Hydro::EntitySerializer.repository(@comment.repository),
          repository_owner: Hydro::EntitySerializer.user(@comment.repository.owner),
          discussion_id: @comment.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@comment.discussion),
          discussion_comment_id: @comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment),
          actor_id: @owner.id,
          actor: Hydro::EntitySerializer.user(@owner),
          action: :ACTION_COMMENT_DELETED,
          action_timestamp: Time.now,
          specimen_body: Hydro::EntitySerializer.specimen_data(@comment.body)
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentDelete")

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsComment")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsComment")
      end
    end

    test "logs deletion event when wiped" do
      travel_to Time.now do
        # Create child comment so the parent comment record cannot be removed, only
        # have its user and body wiped
        create(:discussion_comment, discussion: @unanswered_discussion, parent_comment: @comment)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")

        reset_hydro

        @comment.wipe_or_destroy(@owner)

        assert DiscussionComment.exists?(@comment.id)
        assert_equal "", @comment.reload.body
        refute_nil @comment.deleted_at

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment),
          actor: Hydro::EntitySerializer.user(@owner),
          discussion: Hydro::EntitySerializer.discussion(@unanswered_discussion),
          author: Hydro::EntitySerializer.user(@comment.user),
          discussion_author: Hydro::EntitySerializer.user(@unanswered_discussion.user),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentDelete")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentDelete")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentUpdate")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          discussion_id: @unanswered_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@unanswered_discussion),
          discussion_comment_id: @comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment),
          actor_id: @owner.id,
          actor: Hydro::EntitySerializer.user(@owner),
          action: :ACTION_COMMENT_DELETED,
          action_timestamp: Time.now,
          specimen_body: Hydro::EntitySerializer.specimen_data(@comment.body)
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsComment")
        # 2 messages are published for the wipe, one for the update and one for the delete
        assert_hydro_messages(count: 2, schema: "github.discussions.v2.DiscussionsComment")
      end
    end

    test "logs event on comment update" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
        @comment.actor = @staff
        new_body = "Something borrowed, something blue"

        @comment.update_body(new_body, @comment.actor)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment.reload),
          actor: Hydro::EntitySerializer.user(@staff),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          specimen_body: Hydro::EntitySerializer.specimen_data(new_body),
          discussion: Hydro::EntitySerializer.discussion(@unanswered_discussion),
          author: Hydro::EntitySerializer.user(@comment.user),
          discussion_author: Hydro::EntitySerializer.user(@unanswered_discussion.user),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          feature_flags: []
        }

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentUpdate")
        end

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @comment.repository.id,
          repository: Hydro::EntitySerializer.repository(@comment.repository),
          repository_owner: Hydro::EntitySerializer.user(@comment.repository.owner),
          discussion_id: @comment.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@comment.discussion),
          discussion_comment_id: @comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment),
          actor_id: @comment.actor.id,
          actor: Hydro::EntitySerializer.user(@comment.actor),
          action: :ACTION_COMMENT_UPDATED,
          action_timestamp: Time.now,
          specimen_body: Hydro::EntitySerializer.specimen_data(@comment.body)
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsComment")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsComment")
      end
    end

    test "DiscussionComment update publishes github.platform_health.v1.UserGeneratedContent" do
      reset_hydro
      @comment.actor = @staff
      new_body = "Something borrowed, something blue"

      @comment.update_body(new_body, @comment.actor)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :UPDATE,
        content_type: :DISCUSSION_COMMENT,
        actor: Hydro::EntitySerializer.user(@comment.actor),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.discussions.v1.DiscussionCommentUpdate"),
        content_database_id: @comment.id,
        content_global_relay_id: @comment.global_relay_id,
        content_created_at: @comment.created_at,
        content_updated_at: @comment.updated_at,
        content: Hydro::EntitySerializer.specimen_data(@comment.body),
        parent_content_author: Hydro::EntitySerializer.user(@comment.discussion.author),
        parent_content_database_id: @comment.discussion.id,
        parent_content_global_relay_id: @comment.discussion.global_relay_id,
        parent_content_created_at: @comment.discussion.created_at,
        parent_content_updated_at: @comment.discussion.updated_at,
        owner: Hydro::EntitySerializer.repository_owner(@comment.discussion.repository),
        repository: Hydro::EntitySerializer.repository(@comment.discussion.repository),
        content_visibility: :PUBLIC,
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "does not include specimen data when updating a comment in a private repo" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @private_comment.actor = @staff

        @private_comment.update_body("Something borrowed, something blue", @private_comment.actor)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@private_comment.reload),
          actor: Hydro::EntitySerializer.user(@staff),
          specimen_body: nil,
          discussion: Hydro::EntitySerializer.discussion(@private_discussion),
          author: Hydro::EntitySerializer.user(@private_comment.user),
          discussion_author: Hydro::EntitySerializer.user(@private_discussion.user),
          repository: Hydro::EntitySerializer.repository(@private_repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          feature_flags: []
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentUpdate")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @private_comment.repository.id,
          repository: Hydro::EntitySerializer.repository(@private_comment.repository),
          repository_owner: Hydro::EntitySerializer.user(@private_comment.repository.owner),
          discussion_id: @private_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@private_comment.discussion),
          discussion_comment_id: @private_comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@private_comment),
          actor_id: @staff.id,
          actor: Hydro::EntitySerializer.user(@staff),
          action: :ACTION_COMMENT_UPDATED,
          action_timestamp: Time.now,
          specimen_body: nil,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsComment")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsComment")
      end
    end

    test "logs event when marking as answer" do
      travel_to Time.now do
        @comment.mark_as_answer(actor: @owner)

        message = {
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment.reload),
          actor: Hydro::EntitySerializer.user(@owner),
          discussion: Hydro::EntitySerializer.discussion(@unanswered_discussion.reload),
          author: Hydro::EntitySerializer.user(@comment.user),
          discussion_author: Hydro::EntitySerializer.user(@unanswered_discussion.user),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
        }

        message_v2 = {
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          discussion_id: @unanswered_discussion.id,
          discussion_comment_id: @comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@comment.reload),
          actor_id: @owner&.id,
          actor: Hydro::EntitySerializer.user(@owner),
          action: :MARKED_AS_ANSWER,
          action_timestamp: Time.now,
        }

        assert_hydro_published(message,
          schema: "github.discussions.v1.DiscussionCommentMarkAsAnswer")

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentMarkedAsAnswer")
      end
    end

    test "logs event when unmarking as answer" do
      travel_to Time.now do
        @answer.unmark_as_answer(actor: @owner)

        message = {
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@answer.reload),
          actor: Hydro::EntitySerializer.user(@owner),
          discussion: Hydro::EntitySerializer.discussion(@answered_discussion.reload),
          author: Hydro::EntitySerializer.user(@answer.user),
          discussion_author: Hydro::EntitySerializer.user(@answered_discussion.user),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
        }

        message_v2 = {
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          discussion_id: @answered_discussion.id,
          discussion_comment_id: @answer.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@answer.reload),
          actor_id: @owner&.id,
          actor: Hydro::EntitySerializer.user(@owner),
          action: :UNMARKED_AS_ANSWER,
          action_timestamp: Time.now,
        }

        assert_hydro_published(message,
          schema: "github.discussions.v1.DiscussionCommentUnmarkAsAnswer")

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentMarkedAsAnswer")
      end
    end
  end

  context "unminimize a comment" do
    test "only staff can unminimize staff-minimized comment" do
      @matrix.each_subject { |comment| comment.update(comment_hidden_by: ROLES[:minimized_by_staff]) }

      @matrix.user_scenarios(:async_unminimizable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
      assert @org_comment.async_unminimizable_by?(@staff_user).sync
    end

    test "write+ & staff can unminimize maintainer-minimized comment" do
      @matrix.each_subject { |comment| comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer]) }

      @matrix.user_scenarios(:async_unminimizable_by?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )

      @matrix.each_subject { |_comment| assert @org_comment.async_unminimizable_by?(@staff_user).sync }
    end

    test "write+, staff & the commenting author can unminimize author-minimized comment" do
      @matrix.each_subject { |comment| comment.update(comment_hidden_by:  ROLES[:minimized_by_author]) }

      @matrix.user_scenarios(:async_unminimizable_by?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )

      @matrix.each_subject do |comment|
        assert comment.async_unminimizable_by?(comment.user).sync
        assert comment.async_unminimizable_by?(@staff_user).sync
      end
    end

    test "stores the right comment hidden by value" do
      author_minimized_comment = create(:discussion_comment, repository: @org_repo,
                                        discussion: @org_discussion)
      author_minimized_comment.set_minimized(@reader, "reason", "spam", @reader, staff = false)

      maintainer_minimized_comment = create(:discussion_comment, repository: @org_repo,
                                            discussion: @org_discussion)
      maintainer_minimized_comment.set_minimized(@maintainer, "reason", "spam", @reader, staff = false)

      staff_minimized_comment = create(:discussion_comment, repository: @org_repo,
                                       discussion: @org_discussion)
      staff_minimized_comment.set_minimized(@staff_user, "reason", "spam", @reader, staff = true)

      assert_equal("minimized_by_author", author_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_maintainer", maintainer_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_staff", staff_minimized_comment.comment_hidden_by)
    end

    context "#threaded?" do
      test "if the discussion_comment has a parent it returns true" do
        discussion_comment = create(:discussion_comment, :nested)
        assert discussion_comment.threaded?
      end

      test "if the discussion_comment doesn't have parent it returns false" do
        discussion_comment = create(:discussion_comment)

        assert_equal false, discussion_comment.threaded?
      end
    end
  end

  context "counter cache" do
    test "adds to the counter cache when nested comments are added" do
      discussion = create(:discussion)
      discussion_comment = create(:discussion_comment, discussion: discussion)

      assert_changes "discussion_comment.nested_comments_count", from: 0, to: 1 do
        create(:discussion_comment, discussion: discussion, parent_comment: discussion_comment)
      end
    end

    test "subtracts from the counter cache when nested comments are destroyed" do
      discussion = create(:discussion)
      discussion_comment = create(:discussion_comment, discussion: discussion)
      nested_comment = create(
        :discussion_comment,
        discussion: discussion,
        parent_comment: discussion_comment,
      )

      assert_changes "discussion_comment.nested_comments_count", from: 1, to: 0 do
        nested_comment.destroy
      end
    end
  end

  test "creates an upvote after create" do
    comment = assert_difference("DiscussionCommentVote.count", 1) do
      create(:discussion_comment)
    end

    assert_equal 1, comment.votes.count
  end

  test "does not create an upvote after create if comment is nested" do
    DiscussionComment.any_instance.stubs(:nested?).returns(true)
    comment = assert_difference("DiscussionCommentVote.count", 0) do
      create(:discussion_comment)
    end

    assert_equal 0, comment.votes.count
  end

  context "daily contributors count job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        create(:discussion_comment, discussion: @unanswered_discussion, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      comment = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion_comment, discussion: @unanswered_discussion, created_at: ts)
      end

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        comment.destroy
      end
    end
  end

  def assert_comment_can_be_unmarked_as_answer(comment, user:)
    assert comment.can_unmark_as_answer?(user), "expected #can_unmark_as_answer? to be true"

    result = DiscussionComment.can_unmark_as_answer_by_comment_id(comment.discussion, actor: user)
    assert result[comment.id], "expected #can_unmark_as_answer_by_comment_id to be true"
  end

  def refute_comment_can_be_unmarked_as_answer(comment, user:)
    refute comment.can_unmark_as_answer?(user), "expected #can_unmark_as_answer? to be false"
    refute comment.async_can_unmark_as_answer?(user).sync, "expected #async_can_unmark_as_answer? to be false"

    result = DiscussionComment.can_unmark_as_answer_by_comment_id(comment.discussion, actor: user)
    refute result[comment.id], "expected #can_unmark_as_answer_by_comment_id to be false"
  end

  def assert_comment_reactable(comment, user:, discussion: nil)
    assert comment.reactable_by?(user), "expected #reactable_by? to be true"

    discussion ||= comment.discussion
    result = DiscussionComment.can_react_by_comment_id(discussion, actor: user)
    assert result[comment.id], "expected #can_react_by_comment_id to be true"
  end

  def refute_comment_reactable(comment, user:, discussion: nil)
    refute comment.reactable_by?(user), "expected #reactable_by? to be false"

    discussion ||= comment.discussion
    result = DiscussionComment.can_react_by_comment_id(discussion, actor: user)
    refute result[comment.id], "expected #can_react_by_comment_id to be false"
  end

  def assert_comment_modifiable(comment, user:, discussion: nil)
    assert comment.modifiable_by?(user), "expected #modifiable_by? to be true"
    assert comment.async_modifiable_by?(user).sync, "expected #async_modifiable_by? to be true"
  end

  def refute_comment_modifiable(comment, user:)
    refute comment.modifiable_by?(user), "expected #modifiable_by? to be false"
    refute comment.async_modifiable_by?(user).sync, "expected #async_modifiable_by? to be false"
  end

  def assert_comment_deletable(comment, user:)
    assert comment.deletable_by?(user), "expected #deletable_by? to be true"
  end

  def refute_comment_deletable(comment, user:)
    refute comment.deletable_by?(user), "expected #deletable_by? to be false"
  end

  test "supports emoji for body" do
    comment = create(:discussion_comment, body: "we ❤️ emojis")

    assert_multibyte_tracked_changes(comment, :body)
  end
end
