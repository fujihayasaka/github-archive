# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionReactionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:verified_user)
    @repo = create(:repository, owner: @owner, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)

    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)
    @org_repo = create(:repository, owner: @org, has_discussions: true)
    @org_discussion = create(:discussion, repository: @org_repo)

    @org_private_repo = create(:private_repository, owner: @org, has_discussions: true)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)

    @org_member = create(:verified_user)
    @org.add_member(@org_member)
  end

  context "label" do
    test "returns the label associated with the reaction's content" do
      discussion_reaction = build(:discussion_reaction, content: "smile")

      assert_equal "laugh", discussion_reaction.emotion.label
    end
  end

  context "emoji_character" do
    test "returns the emoji character that the reaction's content represents" do
      discussion_reaction = build(:discussion_reaction, content: "+1")

      assert_equal Emoji.find_by_alias("+1"), discussion_reaction.emotion.emoji_character
    end
  end

  context "DiscussionReaction.react" do
    test "creates discussion reactions when they don't exist between discussion and user" do
      user = create(:verified_user)
      discussion = create(:discussion)

      refute_predicate user.discussion_reactions, :any?

      reaction = DiscussionReaction.react(
        user: user,
        discussion_id: discussion.id,
        content: "+1",
      )

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.discussion_reactions.reload
      assert_same_elements [reaction], discussion.reactions.reload
    end

    test "is idempotent with respect to creating reactions" do
      user = create(:verified_user)
      discussion = create(:discussion)

      reaction = T.let(nil, T.nilable(DiscussionReaction))
      repeated_reactions = []

      assert_difference "DiscussionReaction.count", 1 do
        reaction = DiscussionReaction.react(user: user, discussion_id: discussion.id, content: "+1")
        repeated_reactions = [
          DiscussionReaction.react(user: user, discussion_id: discussion.id, content: "+1"),
          DiscussionReaction.react(user: user, discussion_id: discussion.id, content: "+1"),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |reaction| assert_predicate reaction, :exists? }
      assert_same_elements [reaction], user.discussion_reactions.reload
      assert_same_elements [reaction], discussion.reactions.reload
    end

    test "does nothing when a reaction already exists between discussion and user" do
      discussion_reaction = create(
        :discussion_reaction,
        user: create(:verified_user),
        discussion: create(:discussion),
      )

      assert_no_difference "DiscussionReaction.count" do
        DiscussionReaction.react(
          user: discussion_reaction.user,
          discussion_id: discussion_reaction.discussion_id,
          content: discussion_reaction.content,
        )
      end
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      user = create(:verified_user)
      discussion = create(:discussion)

      returned_reaction = T.let(nil, T.nilable(DiscussionReaction))

      assert_no_difference "DiscussionReaction.count" do
        returned_reaction = DiscussionReaction.react(
          user: user,
          discussion_id: discussion.id,
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
      blocked_user = create(:verified_user).tap { |user| @discussion.author.block(user) }

      returned_reaction = T.let(nil, T.nilable(DiscussionReaction))

      assert_no_difference "DiscussionReaction.count" do
        returned_reaction = DiscussionReaction.react(
          user: blocked_user,
          discussion_id: @discussion.id,
          content: "+1",
        )
      end

      refute_predicate returned_reaction, :valid?
      assert(
        T.must(returned_reaction).errors.messages.keys.include?(:content),
        "reaction should be invalid because of its content",
      )
    end

    test "triggers websocket notification" do
      user = create(:verified_user)
      discussion = create(:discussion)

      freeze_time do
        GitHub::WebSocket.expects(:notify_discussion_channel).with(
          discussion,
          GitHub::WebSocket::Channels.discussion(discussion),
          timestamp: Time.now.to_i,
          wait: discussion.default_live_updates_wait,
          reason: "discussion ##{discussion.id} updated",
          gid: discussion.global_relay_id,
        )

        DiscussionReaction.react(
          user: user,
          discussion_id: discussion.id,
          content: "+1",
        )
      end
    end
  end

  context "DiscussionReaction.unreact" do
    test "destroys reactions between discussion and user" do
      discussion_reaction = create(:discussion_reaction)

      destroyed_reaction = T.let(nil, T.nilable(DiscussionReaction))

      assert_difference "DiscussionReaction.count", -1 do
        destroyed_reaction = DiscussionReaction.unreact(
          user: discussion_reaction.user,
          discussion_id: discussion_reaction.discussion_id,
          content: discussion_reaction.content,
        )
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      discussion_reaction = create(:discussion_reaction)

      other_reaction = T.let(nil, T.nilable(DiscussionReaction))

      assert_difference "DiscussionReaction.count", -1 do
        destroyed_reaction = DiscussionReaction.unreact(
          user: discussion_reaction.user,
          discussion_id: discussion_reaction.discussion_id,
          content: discussion_reaction.content,
        )
        other_reaction = DiscussionReaction.unreact(
          user: destroyed_reaction.user,
          discussion_id: destroyed_reaction.discussion_id,
          content: destroyed_reaction.content,
        )
      end

      assert_predicate other_reaction, :valid?
      refute_predicate other_reaction, :persisted?
    end

    test "does not destroy reactions when the user does not have permission on the subject" do
      user = create(:verified_user)
      reacting_user = create(:verified_user)
      discussion_reaction = create(:discussion_reaction, user: reacting_user)

      assert_no_difference "DiscussionReaction.count" do
        DiscussionReaction.unreact(
          user: user,
          discussion_id: discussion_reaction.discussion.id,
          content: discussion_reaction.content,
        )
      end
    end

    test "triggers websocket notification" do
      user = create(:verified_user)
      discussion = create(:discussion)
      discussion_reaction = create(
        :discussion_reaction,
        discussion: discussion,
        user: user,
      )

      freeze_time do
        GitHub::WebSocket.expects(:notify_discussion_channel).with(
          discussion,
          GitHub::WebSocket::Channels.discussion(discussion),
          timestamp: Time.now.to_i,
          wait: discussion.default_live_updates_wait,
          reason: "discussion ##{discussion.id} updated",
          gid: discussion.global_relay_id,
        )

        DiscussionReaction.unreact(
          user: user,
          discussion_id: discussion.id,
          content: discussion_reaction.content,
        )
      end
    end
  end

  context "DiscussionReaction.async_viewer_can_react?" do
    if GitHub.email_verification_enabled?
      context "when the user does not have verified emails" do
        test "returns false" do
          user = create(:user)
          refute DiscussionReaction.async_viewer_can_react?(user, @discussion).sync
        end
      end
    end

    context "when the user has verified emails" do
      context "when the viewer is blocked by the author" do
        test "returns false" do
          blocked_user = create(:verified_user)
          @discussion.user.block(blocked_user)

          refute DiscussionReaction.async_viewer_can_react?(blocked_user, @discussion).sync
        end
      end

      context "when the viewer is not blocked by the author" do
        context "when the discussion is locked" do
          test "returns false" do
            @discussion.lock(actor: @owner)

            refute DiscussionReaction.async_viewer_can_react?(create(:verified_user), @discussion).sync
          end

          test "returns true for the repo owner" do
            @discussion.lock(actor: @owner)

            assert DiscussionReaction.async_viewer_can_react?(@owner, @discussion).sync
          end

          test "returns true for user with admin access" do
            @org_discussion.lock(actor: @owner)

            admin = create(:verified_user)
            @org_repo.add_member(admin, action: :admin)

            assert DiscussionReaction.async_viewer_can_react?(admin, @org_discussion).sync
          end
        end

        context "when the discussion is not locked" do
          test "returns true" do
            assert DiscussionReaction.async_viewer_can_react?(create(:verified_user), @discussion).sync
          end
        end

        context "when the discussion's repository is not allowing interactions" do
          if GitHub.interaction_limits_enabled?
            test "returns false" do
              interaction = RepositoryInteractionAbility.new(@discussion.repository)
              interaction.set_ability(:sockpuppet_disallowed, @discussion.repository.owner)

              refute DiscussionReaction.async_viewer_can_react?(create(:verified_user), @discussion).sync
            end
          end
        end

        context "when a private repository is in an org" do
          context "when the org has default repo permissions :read" do
            test "returns true when the user is an org member" do
              assert_equal :read, @org.default_repository_permission

              assert DiscussionReaction.async_viewer_can_react?(@org_member, @org_private_discussion).sync
            end
          end

          context "when the org has default repo permissions :none" do
            test "returns false when the user is an org member" do
              perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
                @org.update_default_repository_permission(:none, actor: @org_admin)
              end

              refute DiscussionReaction.async_viewer_can_react?(@org_member, @org_private_discussion).sync
            end

            test "returns true when the user is a repo member" do
              perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
                @org.update_default_repository_permission(:none, actor: @org_admin)
              end

              repo_member = create(:verified_user)
              @org_private_repo.add_member(repo_member, action: :read)

              assert DiscussionReaction.async_viewer_can_react?(repo_member, @org_private_discussion).sync
            end
          end
        end
      end
    end

    context "with an IntegrationInstallation" do
      test "returns true if the integration is installed with discussions write permissions" do


        repo = @discussion.repository
        owner = repo.owner
        installation = make_integration_installation(target: owner, permissions: { "discussions" => :write })

        assert DiscussionReaction.actor_can_react_to?(installation, @discussion)
      end

      test "returns false if the integration does not have sufficient permissions" do


        repo = @discussion.repository
        owner = repo.owner
        installation = make_integration_installation(target: owner, permissions: { "discussions" => :read })

        refute DiscussionReaction.actor_can_react_to?(installation, @discussion)
      end

      test "returns false if the integration is not installed on the repository" do


        installation = make_integration_installation(
          target: create(:verified_user),
          permissions: { "discussions" => :write },
        )

        refute DiscussionReaction.actor_can_react_to?(installation, @discussion)
      end
    end
  end

  context "DiscussionReaction::Status" do
    test "responds to created?" do
      invalid_reaction = DiscussionReaction::RecordStatus.new([DiscussionReaction.new, :invalid])
      created_reaction = DiscussionReaction::RecordStatus.new([DiscussionReaction.new, :created])

      refute_predicate invalid_reaction, :created?
      assert_predicate created_reaction, :created?
    end

    test "responds to exists?" do
      deleted_reaction = DiscussionReaction::RecordStatus.new([DiscussionReaction.new, :deleted])
      existing_reaction = DiscussionReaction::RecordStatus.new([DiscussionReaction.new, :exists])

      refute_predicate deleted_reaction, :exists?
      assert_predicate existing_reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      reaction = DiscussionReaction.new

      assert_raises(ArgumentError, "Invalid status: erased") do
        DiscussionReaction::RecordStatus.new([reaction, :erased])
      end
    end
  end

  context "discussions daily contributors job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        create(:discussion_reaction, discussion: @discussion, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")

      reaction = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion_reaction, discussion: @discussion, created_at: ts)
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

      reaction = DiscussionReaction.react(user: user, discussion_id: @discussion.id, content: "+1")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        discussion: Hydro::EntitySerializer.discussion(@discussion),
        spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
        repository: Hydro::EntitySerializer.repository(@discussion.repository),
        repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
        author: Hydro::EntitySerializer.user(@discussion.user),
        content: "+1",
      }

      assert_hydro_published(message, schema: "github.discussions.v1.DiscussionReactionCreate")
      assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionReactionCreate")

      message_v2 = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository_id: @discussion.repository.id,
        repository: Hydro::EntitySerializer.repository(@discussion.repository),
        repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
        actor_id: user.id,
        actor: Hydro::EntitySerializer.user(user),
        discussion_id: @discussion.id,
        discussion: Hydro::EntitySerializer.discussion(@discussion),
        action: :ACTION_REACTION_ADDED,
        action_timestamp: reaction.created_at,
        reaction: "REACTION_#{reaction.emotion.platform_enum}".to_sym,
      }

      assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsReaction")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsReaction")
    end

    test "logs event on deletion of an existing reaction" do
      travel_to Time.now do
        user = create(:verified_user)
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        reaction = DiscussionReaction.react(user: user, discussion_id: @discussion.id, content: "+1")

        reset_hydro

        DiscussionReaction.unreact(user: user, discussion_id: @discussion.id, content: "+1")

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(user),
          discussion: Hydro::EntitySerializer.discussion(@discussion),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          repository: Hydro::EntitySerializer.repository(@discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
          author: Hydro::EntitySerializer.user(@discussion.user),
          content: "+1",
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionReactionDestroy")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionReactionDestroy")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@discussion.repository.owner),
          actor_id: user.id,
          actor: Hydro::EntitySerializer.user(user),
          discussion_id: @discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@discussion),
          action: :ACTION_REACTION_REMOVED,
          action_timestamp: Time.now,
          reaction: "REACTION_#{reaction.emotion.platform_enum}".to_sym,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsReaction")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsReaction")
      end
    end
  end

  test "destroying succeeds when the discussion is already deleted" do
    reaction = create(:discussion_reaction)
    Discussion.where(id: reaction.discussion.id).delete_all
    reaction.reload

    assert_nil reaction.discussion

    assert_nothing_raised do
      reaction.destroy
    end
  end

  test "destroying succeeds when the repository is deleted" do
    reaction = create(:discussion_reaction)
    Repository.where(id: reaction.repository.id).delete_all
    reaction.reload

    assert_nil reaction.repository

    assert_nothing_raised do
      reaction.destroy
    end
  end
end
