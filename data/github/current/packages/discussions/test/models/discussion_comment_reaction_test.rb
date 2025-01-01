# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentReactionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:verified_user)

    @owner = create(:verified_user)
    @repo = create(:repository, owner: @owner, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
    @discussion_comment = create(:discussion_comment, discussion: @discussion, repository: @repo)

    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)

    @org_repo = create(:repository, owner: @org, has_discussions: true)
    @org_discussion = create(:discussion, repository: @org_repo)
    @org_discussion_comment = create(:discussion_comment, discussion: @org_discussion, repository: @org_repo)

    @org_private_repo = create(:private_repository, owner: @org, has_discussions: true)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_private_comment = create(:discussion_comment, discussion: @org_private_discussion, repository: @org_private_repo)

    @org_member = create(:verified_user)
    @org.add_member(@org_member)
  end

  context "label" do
    test "returns the label associated with the reaction's content" do
      discussion_comment_reaction = build(:discussion_comment_reaction, content: "smile")

      assert_equal "laugh", discussion_comment_reaction.emotion.label
    end
  end

  context "emoji_character" do
    test "returns the emoji character that the reaction's content represents" do
      discussion_comment_reaction = build(:discussion_comment_reaction, content: "+1")

      assert_equal Emoji.find_by_alias("+1"), discussion_comment_reaction.emotion.emoji_character
    end
  end

  context "DiscussionCommentReaction.react" do
    test "creates discussion comment reactions when they don't exist between comment and user" do
      discussion_comment = create(:discussion_comment)

      refute_predicate @user.discussion_comment_reactions, :any?

      reaction = DiscussionCommentReaction.react(
        user: @user,
        discussion_comment_id: discussion_comment.id,
        content: "+1",
      )

      assert_predicate reaction, :created?
      assert_same_elements [reaction], @user.discussion_comment_reactions.reload
      assert_same_elements [reaction], discussion_comment.reactions.reload
    end

    test "is idempotent with respect to creating reactions" do
      discussion_comment = create(:discussion_comment)

      reaction = T.let(nil, T.nilable(DiscussionCommentReaction))
      repeated_reactions = []

      assert_difference "DiscussionCommentReaction.count", 1 do
        reaction = DiscussionCommentReaction.react(
          user: @user,
          discussion_comment_id: discussion_comment.id,
          content: "+1",
        )
        repeated_reactions = [
          DiscussionCommentReaction.react(
            user: @user,
            discussion_comment_id: discussion_comment.id,
            content: "+1",
          ),
          DiscussionCommentReaction.react(
            user: @user,
            discussion_comment_id: discussion_comment.id,
            content: "+1",
          ),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |reaction| assert_predicate reaction, :exists? }
      assert_same_elements [reaction], @user.discussion_comment_reactions.reload
      assert_same_elements [reaction], discussion_comment.reactions.reload
    end

    test "does nothing when a reaction already exists between comment and user" do
      discussion_comment_reaction = create(
        :discussion_comment_reaction,
        user: create(:user),
        discussion_comment: create(:discussion_comment),
      )

      assert_no_difference "DiscussionCommentReaction.count" do
        DiscussionCommentReaction.react(
          user: discussion_comment_reaction.user,
          discussion_comment_id: discussion_comment_reaction.discussion_comment_id,
          content: discussion_comment_reaction.content,
        )
      end
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      user = create(:user)
      discussion_comment = create(:discussion_comment)

      returned_reaction = T.let(nil, T.nilable(DiscussionCommentReaction))

      assert_no_difference "DiscussionCommentReaction.count" do
        returned_reaction = DiscussionCommentReaction.react(
          user: user,
          discussion_comment_id: discussion_comment.id,
          content: "INVALID CONTENT",
        )
      end

      refute_predicate returned_reaction, :valid?
      assert(
        T.must(returned_reaction).errors.messages.keys.include?(:content),
        "reaction should be invalid because of its content",
      )
    end

    test "does nothing when the reacting user has been blocked by the author" do
      blocked_user = create(:user).tap { |user| @discussion_comment.author.block(user) }
      returned_reaction = T.let(nil, T.nilable(DiscussionCommentReaction))

      assert_no_difference "DiscussionCommentReaction.count" do
        returned_reaction = DiscussionCommentReaction.react(
          user: blocked_user,
          discussion_comment_id: @discussion_comment.id,
          content: "+1",
        )
      end

      refute_predicate returned_reaction, :valid?
      assert(
        T.must(returned_reaction).errors.messages.keys.include?(:content),
        "reaction should be invalid because the user has been blocked by the discussion comment "\
          "author"
      )
    end

    test "triggers websocket notification" do
      discussion_comment = create(:discussion_comment)

      freeze_time do
        GitHub::WebSocket.expects(:notify_discussion_channel).with(
          discussion_comment.discussion,
          GitHub::WebSocket::Channels.discussion(discussion_comment.discussion),
          timestamp: Time.now.to_i,
          wait: discussion_comment.default_live_updates_wait,
          reason: "discussion comment ##{discussion_comment.id} updated",
          gid: discussion_comment.global_relay_id,
        )

        DiscussionCommentReaction.react(
          user: @user,
          discussion_comment_id: discussion_comment.id,
          content: "+1",
        )
      end
    end
  end

  context "DiscussionCommentReaction.unreact" do
    test "destroys reactions between discussion comment and user" do
      discussion_comment_reaction = create(:discussion_comment_reaction)

      destroyed_reaction = T.let(nil, T.nilable(DiscussionCommentReaction))

      assert_difference "DiscussionCommentReaction.count", -1 do
        destroyed_reaction = DiscussionCommentReaction.unreact(
          user: discussion_comment_reaction.user,
          discussion_comment_id: discussion_comment_reaction.discussion_comment_id,
          content: discussion_comment_reaction.content,
        )
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      discussion_comment_reaction = create(:discussion_comment_reaction)

      other_reaction = T.let(nil, T.nilable(DiscussionCommentReaction))

      assert_difference "DiscussionCommentReaction.count", -1 do
        destroyed_reaction = DiscussionCommentReaction.unreact(
          user: discussion_comment_reaction.user,
          discussion_comment_id: discussion_comment_reaction.discussion_comment_id,
          content: discussion_comment_reaction.content,
        )
        other_reaction = DiscussionCommentReaction.unreact(
          user: destroyed_reaction.user,
          discussion_comment_id: destroyed_reaction.discussion_comment_id,
          content: destroyed_reaction.content,
        )
      end

      assert_predicate other_reaction, :valid?
      refute_predicate other_reaction, :persisted?
    end

    test "does not destroy reactions when the user does not have permission on the subject" do
      user = create(:user)
      reacting_user = create(:user)
      discussion_comment_reaction = create(:discussion_comment_reaction, user: reacting_user)

      assert_no_difference "DiscussionCommentReaction.count" do
        DiscussionCommentReaction.unreact(
          user: user,
          discussion_comment_id: discussion_comment_reaction.discussion_comment.id,
          content: discussion_comment_reaction.content,
        )
      end
    end

    test "triggers websocket notification" do
      discussion_comment = create(:discussion_comment)
      discussion_comment_reaction = create(
        :discussion_comment_reaction,
        discussion_comment: discussion_comment,
        user: discussion_comment.user,
      )

      freeze_time do
        GitHub::WebSocket.expects(:notify_discussion_channel).with(
          discussion_comment.discussion,
          GitHub::WebSocket::Channels.discussion(discussion_comment.discussion),
          timestamp: Time.now.to_i,
          wait: discussion_comment.default_live_updates_wait,
          reason: "discussion comment ##{discussion_comment.id} updated",
          gid: discussion_comment.global_relay_id,
        )

        DiscussionCommentReaction.unreact(
          user: discussion_comment.user,
          discussion_comment_id: discussion_comment.id,
          content: discussion_comment_reaction.content,
        )
      end
    end
  end

  context "DiscussionCommentReaction.async_viewer_can_react?" do
    context "when the user does not have verified emails" do
      if GitHub.email_verification_enabled?
        test "returns false" do
          user = create(:user)

          refute DiscussionCommentReaction.async_viewer_can_react?(user, @discussion_comment).sync
        end
      else
        test "returns true" do
          user = create(:user)

          assert DiscussionCommentReaction.async_viewer_can_react?(user, @discussion_comment).sync
        end
      end
    end

    context "when the user has verified emails" do
      context "when the viewer is blocked by the author" do
        test "returns false" do
          blocked_user = create(:user)
          @discussion_comment.user.block(blocked_user)

          refute DiscussionCommentReaction.async_viewer_can_react?(blocked_user, @discussion_comment).sync
        end
      end

      context "when the viewer is not blocked by the author" do
        context "when the discussion is locked" do
          test "returns false" do
            @discussion.lock(actor: @owner)

            refute DiscussionCommentReaction.async_viewer_can_react?(@user, @discussion_comment).sync
          end

          test "returns true for the repo owner" do
            @discussion.lock(actor: @owner)

            assert DiscussionCommentReaction.async_viewer_can_react?(@owner, @discussion_comment).sync
          end

          test "returns true for user with admin access" do
            @org_discussion.lock(actor: @owner)

            admin = create(:verified_user)
            @org_repo.add_member(admin, action: :admin)

            assert DiscussionCommentReaction.async_viewer_can_react?(admin, @org_discussion_comment).sync
          end
        end

        context "when the discussion is not locked" do
          test "returns true" do
            assert DiscussionCommentReaction.async_viewer_can_react?(@user, @discussion_comment).sync
          end
        end

        context "when the discussion's repository is not allowing interactions" do
          if GitHub.interaction_limits_enabled?
            test "returns false" do
              interaction = RepositoryInteractionAbility.new(@discussion_comment.repository)
              interaction.set_ability(:sockpuppet_disallowed, @discussion_comment.repository.owner)

              refute DiscussionCommentReaction.async_viewer_can_react?(
                create(:user),
                @discussion_comment,
              ).sync
            end
          end
        end

        context "when a private repository is in an org" do
          context "when the org has default repo permissions :read" do
            test "returns true when the user is an org member" do
              assert_equal :read, @org.default_repository_permission

              assert DiscussionCommentReaction.async_viewer_can_react?(@org_member, @org_private_comment).sync
            end
          end

          context "when the org has default repo permissions :none" do
            test "returns false when the user is an org member" do
              perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
                @org.update_default_repository_permission(:none, actor: @org_admin)
              end

              refute DiscussionCommentReaction.async_viewer_can_react?(@org_member, @org_private_comment).sync
            end

            test "returns true when the user is a repo member" do
              perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
                @org.update_default_repository_permission(:none, actor: @org_admin)
              end

              repo_member = create(:verified_user)
              @org_private_repo.add_member(repo_member, action: :read)

              assert DiscussionCommentReaction.async_viewer_can_react?(repo_member, @org_private_comment).sync
            end
          end
        end
      end
    end

    context "with an IntegrationInstallation" do
      test "returns true if the integration is installed with discussions write permissions" do


        owner = @discussion_comment.repository.owner
        installation = make_integration_installation(target: owner, permissions: { "discussions" => :write })

        assert DiscussionCommentReaction.actor_can_react_to?(installation, @discussion_comment)
      end

      test "returns false if the integration does not have sufficient permissions" do


        owner = @discussion_comment.repository.owner
        installation = make_integration_installation(target: owner, permissions: { "discussions" => :read })

        refute DiscussionCommentReaction.actor_can_react_to?(installation, @discussion_comment)
      end

      test "returns false if the integration is not installed on the repository" do


        installation = make_integration_installation(
          target: @user,
          permissions: { "discussions" => :write },
        )

        refute DiscussionCommentReaction.actor_can_react_to?(installation, @discussion_comment)
      end
    end
  end

  context "DiscussionCommentReaction::Status" do
    test "responds to created?" do
      invalid_reaction =
        DiscussionCommentReaction::RecordStatus.new([DiscussionCommentReaction.new, :invalid])
      created_reaction =
        DiscussionCommentReaction::RecordStatus.new([DiscussionCommentReaction.new, :created])

      refute_predicate invalid_reaction, :created?
      assert_predicate created_reaction, :created?
    end

    test "responds to exists?" do
      deleted_reaction =
        DiscussionCommentReaction::RecordStatus.new([DiscussionCommentReaction.new, :deleted])
      existing_reaction =
        DiscussionCommentReaction::RecordStatus.new([DiscussionCommentReaction.new, :exists])

      refute_predicate deleted_reaction, :exists?
      assert_predicate existing_reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      reaction = DiscussionCommentReaction.new

      assert_raises(ArgumentError, "Invalid status: erased") do
        DiscussionCommentReaction::RecordStatus.new([reaction, :erased])
      end
    end
  end

  context "daily contributors count job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        create(:discussion_comment_reaction, discussion_comment: @discussion_comment, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      reaction = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion_comment_reaction, discussion_comment: @discussion_comment, created_at: ts)
      end

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        reaction.destroy
      end
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "logs event on creation of a new reaction" do
      user = create(:verified_user)
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

      reaction = DiscussionCommentReaction.react(
        user: user,
        discussion_comment_id: @discussion_comment.id,
        content: "thinking_face",
      )

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        actor: Hydro::EntitySerializer.user(user),
        discussion_comment: Hydro::EntitySerializer.discussion_comment(@discussion_comment),
        discussion: Hydro::EntitySerializer.discussion(@discussion_comment.discussion),
        repository: Hydro::EntitySerializer.repository(@discussion_comment.repository),
        repository_owner: Hydro::EntitySerializer.user(@discussion_comment.repository.owner),
        author: Hydro::EntitySerializer.user(@discussion_comment.user),
        content: "thinking_face",
      }

      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentReactionCreate")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentReactionCreate")

      message_v2 = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository_id: @discussion_comment.repository.id,
        repository: Hydro::EntitySerializer.repository(@discussion_comment.repository),
        repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
        discussion_id: @discussion_comment.discussion.id,
        discussion: Hydro::EntitySerializer.discussion(@discussion_comment.discussion),
        discussion_comment_id: @discussion_comment.id,
        discussion_comment: Hydro::EntitySerializer.discussion_comment(@discussion_comment),
        actor_id: user.id,
        actor: Hydro::EntitySerializer.user(user),
        action: :ACTION_REACTION_ADDED,
        action_timestamp: reaction.created_at,
        reaction: "REACTION_#{reaction.emotion.platform_enum}".to_sym,
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
      }

      assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentReaction")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCommentReaction")
    end

    test "logs event on deletion of an existing reaction" do
      travel_to Time.now do
        user = create(:verified_user)
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
        reaction = DiscussionCommentReaction.react(
          user: user,
          discussion_comment_id: @discussion_comment.id,
          content: "heart",
        )
        reset_hydro

        DiscussionCommentReaction.unreact(user: user, discussion_comment_id: @discussion_comment.id, content: "heart")

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          actor: Hydro::EntitySerializer.user(user),
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@discussion_comment),
          discussion: Hydro::EntitySerializer.discussion(@discussion_comment.discussion),
          repository: Hydro::EntitySerializer.repository(@discussion_comment.repository),
          repository_owner: Hydro::EntitySerializer.user(@discussion_comment.repository.owner),
          author: Hydro::EntitySerializer.user(@discussion_comment.user),
          content: "heart",
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentReactionDestroy")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCommentReactionDestroy")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @discussion_comment.repository.id,
          repository: Hydro::EntitySerializer.repository(@discussion_comment.repository),
          repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
          discussion_id: @discussion_comment.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@discussion_comment.discussion),
          discussion_comment_id: @discussion_comment.id,
          discussion_comment: Hydro::EntitySerializer.discussion_comment(@discussion_comment),
          actor_id: user.id,
          actor: Hydro::EntitySerializer.user(user),
          action: :ACTION_REACTION_DELETED,
          action_timestamp: Time.now,
          reaction: "REACTION_#{reaction.emotion.platform_enum}".to_sym,
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentReaction")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsCommentReaction")
      end
    end
  end

  test "destroying succeeds when the discussion is already deleted" do
    reaction = create(:discussion_comment_reaction)
    DiscussionComment.where(id: reaction.discussion_comment.id).delete_all
    reaction.reload

    assert_nil reaction.discussion_comment

    assert_nothing_raised do
      reaction.destroy
    end
  end

  test "destroying succeeds when the repository is deleted" do
    reaction = create(:discussion_comment_reaction)
    Repository.where(id: reaction.repository.id).delete_all
    reaction.reload

    assert_nil reaction.repository

    assert_nothing_raised do
      reaction.destroy
    end
  end
end
