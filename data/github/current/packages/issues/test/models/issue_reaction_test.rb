# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueReactionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @reaction = create(:issue_reaction)
  end

  context "factories" do
    context "#issue" do
      test "is saved to the database" do
        refute_nil @reaction.issue
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

    context "#issue" do
      test "must not be nil" do
        @reaction.issue = nil
        refute_predicate @reaction, :valid?
      end

      test "must be a valid type" do
        assert_raises ActiveRecord::AssociationTypeMismatch do
          @reaction.issue = create(:organization)
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
      forked.update_attribute(:has_issues, true)

      issue = create(:issue, repository: forked)

      reaction = IssueReaction.react(user: user, subject_id: issue.id, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.issue_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], issue.reactions.reload
    end

    test "is idempotent with respect to creating reactions" do
      user = create(:user)
      issue = create(:issue, user: user)

      reaction = T.let(nil, T.untyped)
      repeated_reactions = []

      assert_difference "IssueReaction.count", 1 do
        reaction = IssueReaction.react(user: user, subject_id: issue.id, content: "+1")
        repeated_reactions = [
           IssueReaction.react(user: user, subject_id: issue.id, content: "+1"),
           IssueReaction.react(user: user, subject_id: issue.id, content: "+1"),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |r| assert_predicate r, :exists? }

      assert_same_elements [reaction], user.issue_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], issue.reactions.reload
    end

    test "does nothing when a reaction already exists between subject and user" do
      user = create(:user)
      issue = create(:issue, user: user)
      reaction = create(:issue_reaction, user: user, issue: issue)

      returned_reaction = T.let(nil, T.untyped)

      assert_no_difference "IssueReaction.count" do
        returned_reaction = IssueReaction.react(user: reaction.user, subject_id: reaction.issue_id, content: reaction.content)
      end

      assert_predicate returned_reaction, :exists?
      assert_equal returned_reaction, reaction
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      user = create(:user)
      issue = create :issue, user: user

      returned_reaction = T.let(nil, T.untyped)

      assert_no_difference "IssueReaction.count" do
        returned_reaction = IssueReaction.react(user: user, subject_id: issue.id, content: "INVALID CONTENT")
      end

      refute_predicate returned_reaction, :valid?
      assert returned_reaction.errors.messages.keys.include?(:content), "reaction should be invalid because of its content"
    end

    if GitHub.interaction_limits_enabled?
      test "does not create reactions when repository interaction is not allowed" do
        user = create(:user)
        repo = create(:repository)
        issue = create(:issue, repository: repo)
        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:sockpuppet_disallowed, repo.owner, staff_actor: true)

        reaction = T.let(nil, T.untyped)

        assert_no_difference "IssueReaction.count" do
          reaction = IssueReaction.react(user: user, subject_id: issue.id, content: "+1")
        end

        refute_predicate reaction, :valid?
      end
    end
  end

  context ".unreact" do
    test "destroys reactions between subject and user" do
      user = create(:user)
      issue = create(:issue, user: user)
      reaction = create(:issue_reaction, user: user, issue: issue)

      destroyed_reaction = T.let(nil, T.untyped)

      assert_difference "IssueReaction.count", -1 do
        destroyed_reaction = IssueReaction.unreact(user: reaction.user, subject_id: reaction.issue_id, content: reaction.content)
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      user = create(:user)
      issue = create(:issue, user: user)
      reaction = create(:issue_reaction, user: user, issue: issue)

      other_reaction = T.let(nil, T.untyped)

      assert_difference "IssueReaction.count", -1 do
        destroyed_reaction = IssueReaction.unreact(user: reaction.user, subject_id: reaction.issue_id, content: reaction.content)
        other_reaction = IssueReaction.unreact(user: destroyed_reaction.user, subject_id: destroyed_reaction.issue_id, content: destroyed_reaction.content)
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
      issue = create(:issue, repository: repo)
      issue = create(:issue, user: user, repository: repo)
      reaction = create(:issue_reaction, user: user, issue: issue)

      # User loses permission on the team that owns the private repo and the
      # subject:
      team.remove_member(user, force: true, send_notification: false)

      assert_no_difference "IssueReaction.count" do
        IssueReaction.unreact(user: user, subject_id: issue.id, content: reaction.content)
      end
    end
  end

  context ".async_viewer_can_react?" do
    test "is true for an unblocked user on an issue" do
      assert IssueReaction.async_viewer_can_react?(create(:user), create(:issue)).sync
    end

    test "is false when issue is locked" do
      issue = create(:issue)
      issue.lock(issue.repository.user)
      refute IssueReaction.async_viewer_can_react?(create(:user), issue).sync
    end

    test "is false when blocked by the repo owner" do
      blocked_user = create(:user)
      issue = create(:issue)
      issue.repository.owner.block(blocked_user)
      refute IssueReaction.async_viewer_can_react?(blocked_user, issue).sync
    end

    test "is false when user is blocked by issue creator" do
      blocked_user = create(:user)
      issue = create(:issue)
      issue.user.block(blocked_user)
      refute IssueReaction.async_viewer_can_react?(blocked_user, issue).sync
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
      reaction = IssueReaction.record_status([IssueReaction.new, :invalid])
      refute_predicate reaction, :created?

      reaction = IssueReaction.record_status([IssueReaction.new, :created])
      assert_predicate reaction, :created?
    end

    test "responds to exists?" do
      reaction = IssueReaction.record_status([IssueReaction.new, :deleted])
      refute_predicate reaction, :exists?

      reaction = IssueReaction.record_status([IssueReaction.new, :exists])
      assert_predicate reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      assert_raises(ArgumentError, "Invalid status: erased") do
        IssueReaction.record_status([IssueReaction.new, :erased])
      end
    end
  end

  test "sends hydro event" do
    reaction = create(:issue_reaction)
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

  context "prelude_reaction_count_for_reaction" do
    test "returns the number of reactions for a given reaction with a single query" do
      user = create(:user)
      issues = []
      10.times do |i|
        issue = create(:issue, user: user)

        # first issue has 1 reactions, second issue has 2, etc.
        (i + 1).times do |_j|
          reaction = create(:issue_reaction, user: create(:verified_user), issue: issue, content: "+1",)
        end

        issues << issue
      end

      assert_query_count_per_table({ issue_reactions: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(issues, :prelude_reaction_count_for_reaction, "+1")
      end

      10.times do |i|
        assert_equal i + 1, issues[i].prelude_reaction_count_for_reaction("+1")
      end
    end
  end
end
