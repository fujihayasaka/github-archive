# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitCommentReactionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @reaction = create(:commit_comment_reaction)
  end

  context "factories" do
    context "#commit_comment" do
      test "is saved to the database" do
        refute_nil @reaction.commit_comment
      end
    end

    context "#repository" do
      test "is saved to the database" do
        refute_nil @reaction.repository
      end
    end

    context "#subject" do
      test "is saved to the database" do
        refute_nil @reaction.subject
      end
    end

    context "#user" do
      test "is saved to the database" do
        refute_nil @reaction.user
      end
    end
  end

  context "validations" do
    test "can be valid" do
      assert_predicate @reaction, :valid?
    end

    context "#commit_comment" do
      test "must not be nil" do
        @reaction.commit_comment = nil
        refute_predicate @reaction, :valid?
      end

      test "must be a invalid type" do
        assert_raises ActiveRecord::AssociationTypeMismatch do
          @reaction.commit_comment = create(:organization)
        end
      end
    end

    context "#content" do
      test "must not be nil" do
        @reaction.content = nil
        refute_predicate @reaction, :valid?
      end

      test "must not be the name of an invalid emoji" do
        @reaction.content = "invalid_emoji"
        refute_predicate @reaction, :valid?
      end
    end

    context "#repository" do
      test "must not be nil" do
        @reaction.repository = nil
        refute_predicate @reaction, :valid?
      end
    end

    context "#user" do
      test "must not be nil" do
        @reaction.user = nil
        refute_predicate @reaction, :valid?
      end
    end
  end

  context ".react" do
    test "creates reactions when the subject's repository is a fork of the current repo (PR)" do
      user = forker = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org, from_example: :review_comment_source)

      forked = create(:fork_repository, forker: forker, fork_repo: repo, from_example: :review_comment_fork)

      commit_comment = create(:commit_comment, user: forker, repository: forked, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")

      reaction = CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.commit_comment_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], commit_comment.reactions.reload
    end

    test "is idempotent with respect to creating reactions" do
      user = create(:user)
      repo = create(:repository, owner: user)
      commit_comment = create(:commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")

      reaction = T.let(nil, T.nilable(CommitCommentReaction))
      repeated_reactions = []

      assert_difference "CommitCommentReaction.count", 1 do
        reaction = CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "+1")
        repeated_reactions = [
           CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "+1"),
           CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "+1"),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |r| assert_predicate r, :exists? }

      assert_same_elements [reaction], user.commit_comment_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], commit_comment.reactions.reload
    end

    test "does nothing when a reaction already exists between subject and user" do
      user = create(:user)
      repo = create(:repository, owner: user)
      commit_comment = create(:commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")
      reaction = create(:commit_comment_reaction, user: user, commit_comment: commit_comment)

      returned_reaction = T.let(nil, T.nilable(CommitCommentReaction))

      assert_no_difference "CommitCommentReaction.count" do
        returned_reaction = CommitCommentReaction.react(user: reaction.user, subject_id: reaction.commit_comment_id, content: reaction.content)
      end

      assert_predicate returned_reaction, :exists?
      assert_equal returned_reaction, reaction
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      user = create(:user)
      repo = create(:repository, owner: user)
      commit_comment = create :commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89"

      returned_reaction = T.let(nil, T.nilable(CommitCommentReaction))

      assert_no_difference "CommitCommentReaction.count" do
        returned_reaction = CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "INVALID CONTENT")
      end

      refute_predicate returned_reaction, :valid?
      assert returned_reaction&.errors.messages.keys.include?(:content), "reaction should be invalid because of its content"
    end

    if GitHub.interaction_limits_enabled?
      test "does not create reactions when repository interaction is not allowed" do
        user = create(:user)
        repo = create(:repository)
        commit_comment = create :commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89"
        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:sockpuppet_disallowed, repo.owner, staff_actor: true)

        reaction = T.let(nil, T.nilable(CommitCommentReaction))

        assert_no_difference "CommitCommentReaction.count" do
          reaction = CommitCommentReaction.react(user: user, subject_id: commit_comment.id, content: "+1")
        end

        refute_predicate reaction, :valid?
      end
    end
  end

  context ".unreact" do
    test "destroys reactions between subject and user" do
      user = create(:user)
      repo = create(:repository, owner: user)
      commit_comment = create(:commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")
      reaction = create(:commit_comment_reaction, user: user, commit_comment: commit_comment)

      destroyed_reaction = T.let(nil, T.nilable(CommitCommentReaction))

      assert_difference "CommitCommentReaction.count", -1 do
        destroyed_reaction = CommitCommentReaction.unreact(user: reaction.user, subject_id: reaction.commit_comment_id, content: reaction.content)
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      user = create(:user)
      repo = create(:repository, owner: user)
      commit_comment = create(:commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")
      reaction = create(:commit_comment_reaction, user: user, commit_comment: commit_comment)

      other_reaction = T.let(nil, T.nilable(CommitCommentReaction))

      assert_difference "CommitCommentReaction.count", -1 do
        destroyed_reaction = CommitCommentReaction.unreact(user: reaction.user, subject_id: reaction.commit_comment_id, content: reaction.content)
        other_reaction = CommitCommentReaction.unreact(user: destroyed_reaction.user, subject_id: destroyed_reaction.commit_comment_id, content: destroyed_reaction.content)
      end

      assert_predicate other_reaction, :valid?
      refute_predicate other_reaction, :persisted?
    end

    test "does not destroy reactions when the user does not have permission on the subject" do
      user = create(:user)
      org = create(:organization)
      team = create(:team, organization: org)
      team.add_member(user)
      repo = create(:private_repository)
      team.add_repository(repo, :pull, allow_different_owner: true)
      commit_comment = create(:commit_comment, user: user, repository: repo, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89")
      reaction = create(:commit_comment_reaction, user: user, commit_comment: commit_comment)

      # User loses permission on the team that owns the private repo and the
      # subject:
      team.remove_member(user, force: true, send_notification: false)

      assert_no_difference "CommitCommentReaction.count" do
        CommitCommentReaction.unreact(user: user, subject_id: commit_comment.id, content: reaction.content)
      end
    end
  end

  context ".async_viewer_can_react?" do
    test "is true for an unblocked user on a commit comment" do
      assert CommitCommentReaction.async_viewer_can_react?(create(:user), create(:commit_comment)).sync
    end

    test "is false when commit is locked" do
      repo = create(:repository, from_example: :simple)
      commit = repo.commits.find("63611721afd41f58f801d66e543d8288b4c5eb44")
      commit_comment = create(:commit_comment, repository: repo, commit_id: commit.oid)
      commit.lock(repo.user)
      refute CommitCommentReaction.async_viewer_can_react?(create(:user), commit_comment).sync
    end

    test "is false when blocked by the repo owner" do
      blocked_user = create(:user)
      commit_comment = create(:commit_comment)
      commit_comment.repository.owner.block(blocked_user)
      refute CommitCommentReaction.async_viewer_can_react?(blocked_user, commit_comment).sync
    end

    test "is false when user is blocked by commit commenter" do
      blocked_user = create(:user)
      commit_comment = create(:commit_comment)
      commit_comment.user.block(blocked_user)
      refute CommitCommentReaction.async_viewer_can_react?(blocked_user, commit_comment).sync
    end
  end

  context "#emotion" do
    test "returns the label associated with the reaction's content" do
      @reaction.content = "smile"
      assert_equal "laugh", @reaction.emotion.label
    end

    test "returns the emoji character that the reaction's content represents" do
      @reaction.content = "+1"
      assert_equal Emoji.find_by_alias("+1"), @reaction.emotion.emoji_character
    end
  end

  context "#record_status" do
    test "responds to created?" do
      reaction = CommitCommentReaction.record_status([CommitCommentReaction.new, :invalid])
      refute_predicate reaction, :created?

      reaction = CommitCommentReaction.record_status([CommitCommentReaction.new, :created])
      assert_predicate reaction, :created?
    end

    test "responds to exists?" do
      reaction = CommitCommentReaction.record_status([CommitCommentReaction.new, :deleted])
      refute_predicate reaction, :exists?

      reaction = CommitCommentReaction.record_status([CommitCommentReaction.new, :exists])
      assert_predicate reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      assert_raises(ArgumentError, "Invalid status: erased") do
        CommitCommentReaction.record_status([CommitCommentReaction.new, :erased])
      end
    end
  end

  test "sends hydro event" do
    reaction = create(:commit_comment_reaction)
    assert_hydro_published_partial({
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      actor: Hydro::EntitySerializer.user(reaction.user),
      subject_type: reaction.subject_type,
      subject_id: reaction.subject_id,
      repository: Hydro::EntitySerializer.repository(reaction.repository),
      repository_owner: Hydro::EntitySerializer.user(reaction.repository&.owner),
      content: reaction.content
    }, schema: "github.v1.ReactionCreate")
  end
end
