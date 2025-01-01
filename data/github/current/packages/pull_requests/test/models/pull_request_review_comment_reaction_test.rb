# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCommentReactionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @reaction = create(:pull_request_review_comment_reaction)

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  # Helper to create these because they need a bunch of supporting objects in
  # order to avoid: "Validation failed: Head sha can't be blank, Base sha can't
  # be blank, No commits between master and topic, Head ref must be a branch,
  # Base ref must be a branch".
  def create_pull_request_review_comment(**kwargs)
    repo = kwargs.delete(:repository) || create(:repository)
    example_repo :simple, repo
    user = kwargs.delete(:user)
    if user
      pull_request = create :pull_request, :with_mergeable_head, repository: repo, user: user
    else
      pull_request = create :pull_request, :with_mergeable_head, repository: repo
    end
    create(:pull_request_review_comment, pull_request: pull_request, **kwargs)
  end

  context "factories" do
    context "#pull_request_review_comment" do
      test "is saved to the database" do
        refute_nil @reaction.pull_request_review_comment
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

    context "#pull_request_review_comment" do
      test "must not be nil" do
        @reaction.pull_request_review_comment = nil
        refute_predicate @reaction, :valid?
      end

      test "must be a valid type" do
        assert_raises ActiveRecord::AssociationTypeMismatch do
          @reaction.pull_request_review_comment = create(:organization)
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

      pull_request_review_comment = create_pull_request_review_comment(user: forker)

      reaction = PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.pull_request_review_comment_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], pull_request_review_comment.reactions.reload
    end

    test "is idempotent with respect to creating reactions" do
      pull_request_review_comment = create_pull_request_review_comment
      user = pull_request_review_comment.user

      reaction = T.let(nil, T.untyped)
      repeated_reactions = []

      assert_difference "PullRequestReviewCommentReaction.count", 1 do
        reaction = PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "+1")
        repeated_reactions = [
           PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "+1"),
           PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "+1"),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |r| assert_predicate r, :exists? }

      assert_same_elements [reaction], user.pull_request_review_comment_reactions.reload
      # TODO: enable this once we start double-writing
      #assert_same_elements [reaction], pull_request_review_comment.reactions.reload
    end

    test "does nothing when a reaction already exists between subject and user" do
      pull_request_review_comment = create_pull_request_review_comment
      user = pull_request_review_comment.user
      reaction = create(:pull_request_review_comment_reaction, user: user, pull_request_review_comment: pull_request_review_comment)

      returned_reaction = T.let(nil, T.untyped)

      assert_no_difference "PullRequestReviewCommentReaction.count" do
        returned_reaction = PullRequestReviewCommentReaction.react(user: reaction.user, subject_id: reaction.pull_request_review_comment_id, content: reaction.content)
      end

      assert_predicate returned_reaction, :exists?
      assert_equal returned_reaction, reaction
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      pull_request_review_comment = create_pull_request_review_comment
      user = pull_request_review_comment.user

      returned_reaction = T.let(nil, T.untyped)

      assert_no_difference "PullRequestReviewCommentReaction.count" do
        returned_reaction = PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "INVALID CONTENT")
      end

      refute_predicate returned_reaction, :valid?
      assert returned_reaction.errors.messages.keys.include?(:content), "reaction should be invalid because of its content"
    end

    test "reaction is invalid if the comment is a code scanning comment" do
      user = create(:user, login: "user")

      repo = create(:repository, from_example: :simple)
      repo.add_member user

      pull = PullRequest.create_for!(repo,
        base: "master",
        head: "cr-line-endings",
        user: user,
        title: "PR",
        body: "body",
      )

      review = pull.build_code_scanning_variant_review do |r|
        r.user = @code_scanning_app.bot
      end

      thread = review.build_thread
      thread.build_first_comment(
        user: @code_scanning_app.bot,
        body: "bad code!",
        path: "a",
        line: 1,
      ).save!
      review.comment!

      comment = thread.comments.first
      reaction = PullRequestReviewCommentReaction.react(user: user, subject_id: comment.id, content: "smile")

      refute_predicate reaction, :valid?
      assert_equal ["code scanning comments cannot be reacted"], reaction.errors[:base]
    end

    if GitHub.interaction_limits_enabled?
      test "does not create reactions when repository interaction is not allowed" do
        pull_request_review_comment = create_pull_request_review_comment
        user = pull_request_review_comment.user
        repo = pull_request_review_comment.pull_request.repository
        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:sockpuppet_disallowed, repo.owner, staff_actor: true)

        reaction = T.let(nil, T.untyped)

        assert_no_difference "PullRequestReviewCommentReaction.count" do
          reaction = PullRequestReviewCommentReaction.react(user: user, subject_id: pull_request_review_comment.id, content: "+1")
        end

        refute_predicate reaction, :valid?
      end
    end
  end

  context ".unreact" do
    test "destroys reactions between subject and user" do
      pull_request_review_comment = create_pull_request_review_comment
      user = pull_request_review_comment.user
      reaction = create(:pull_request_review_comment_reaction, user: user, pull_request_review_comment: pull_request_review_comment)

      destroyed_reaction = T.let(nil, T.untyped)

      assert_difference "PullRequestReviewCommentReaction.count", -1 do
        destroyed_reaction = PullRequestReviewCommentReaction.unreact(user: reaction.user, subject_id: reaction.pull_request_review_comment_id, content: reaction.content)
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      pull_request_review_comment = create_pull_request_review_comment
      user = pull_request_review_comment.user
      reaction = create(:pull_request_review_comment_reaction, user: user, pull_request_review_comment: pull_request_review_comment)

      other_reaction = T.let(nil, T.untyped)

      assert_difference "PullRequestReviewCommentReaction.count", -1 do
        destroyed_reaction = PullRequestReviewCommentReaction.unreact(user: reaction.user, subject_id: reaction.pull_request_review_comment_id, content: reaction.content)
        other_reaction = PullRequestReviewCommentReaction.unreact(user: destroyed_reaction.user, subject_id: destroyed_reaction.pull_request_review_comment_id, content: destroyed_reaction.content)
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
      pull_request_review_comment = create_pull_request_review_comment(user: user, repository: repo)
      reaction = create(:pull_request_review_comment_reaction, user: user, pull_request_review_comment: pull_request_review_comment)

      # User loses permission on the team that owns the private repo and the
      # subject:
      team.remove_member(user, force: true, send_notification: false)

      assert_no_difference "PullRequestReviewCommentReaction.count" do
        PullRequestReviewCommentReaction.unreact(user: user, subject_id: pull_request_review_comment.id, content: reaction.content)
      end
    end
  end

  context ".async_viewer_can_react?" do
    test "is true for an unblocked user on an issue comment" do
      assert PullRequestReviewCommentReaction.async_viewer_can_react?(create(:user), create_pull_request_review_comment).sync
    end

    test "is false when pull request is locked" do
      pull_request_review_comment = create_pull_request_review_comment
      pull_request = pull_request_review_comment.pull_request
      pull_request.issue.lock(pull_request.repository.user)
      refute PullRequestReviewCommentReaction.async_viewer_can_react?(create(:user), pull_request_review_comment).sync
    end

    test "is false when blocked by the repo owner" do
      blocked_user = create(:user)
      pull_request_review_comment = create_pull_request_review_comment
      pull_request_review_comment.repository.owner.block(blocked_user)
      refute PullRequestReviewCommentReaction.async_viewer_can_react?(blocked_user, pull_request_review_comment).sync
    end

    test "is false when user is blocked by issue commenter" do
      blocked_user = create(:user)
      pull_request_review_comment = create_pull_request_review_comment
      pull_request_review_comment.user.block(blocked_user)
      refute PullRequestReviewCommentReaction.async_viewer_can_react?(blocked_user, pull_request_review_comment).sync
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
      reaction = PullRequestReviewCommentReaction.record_status([PullRequestReviewCommentReaction.new, :invalid])
      refute_predicate reaction, :created?

      reaction = PullRequestReviewCommentReaction.record_status([PullRequestReviewCommentReaction.new, :created])
      assert_predicate reaction, :created?
    end

    test "responds to exists?" do
      reaction = PullRequestReviewCommentReaction.record_status([PullRequestReviewCommentReaction.new, :deleted])
      refute_predicate reaction, :exists?

      reaction = PullRequestReviewCommentReaction.record_status([PullRequestReviewCommentReaction.new, :exists])
      assert_predicate reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      assert_raises(ArgumentError, "Invalid status: erased") do
        PullRequestReviewCommentReaction.record_status([PullRequestReviewCommentReaction.new, :erased])
      end
    end
  end

  test "sends hydro event" do
    reaction = create(:pull_request_review_comment_reaction)
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
