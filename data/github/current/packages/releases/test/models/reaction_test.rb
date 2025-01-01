# typed: true
# frozen_string_literal: true

require "test_helper"

class ReactionAssociationsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @reaction = create :reaction
  end

  context "user" do
    test "is saved to the database" do
      refute_nil @reaction.user
    end
  end

  context "subject" do
    test "is saved to the database" do
      refute_nil @reaction.subject
    end
  end

  test "sends hydro event" do
    reaction = create :reaction
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

class ReactionValidationsTest < GitHub::TestCase
  fixtures do
    @reaction = create :reaction
  end

  test "can be valid" do
    assert_predicate @reaction, :valid?
  end

  context "content" do
    test "must not be nil" do
      @reaction.content = nil
      refute_predicate @reaction, :valid?
    end

    test "must not be the name of an invalid emoji" do
      @reaction.content = "invalid_emoji"
      refute_predicate @reaction, :valid?
    end
  end

  context "user" do
    test "must not be nil" do
      @reaction.user = nil
      refute_predicate @reaction, :valid?
    end
  end

  context "subject" do
    test "must not be nil" do
      @reaction.subject = nil
      refute_predicate @reaction, :valid?
    end

    test "must not be an invalid type" do
      @reaction.subject = create(:organization)
      refute_predicate @reaction, :valid?
    end
  end
end

class ReactionTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @issue                       = create(:issue)
    @locked_issue                = create(:issue)
    @issue_comment               = create(:issue_comment)
    @commit_comment              = create(:commit_comment)
    @pull_request                = create(:pull_request, :disable_disk_access)
    @pull_request_review         = -> {
      repo = create(:repository, from_example: :simple)
      pull_request = create :pull_request, :with_mergeable_head, repository: repo
      create(:pull_request_review, pull_request: pull_request)
    }.call
    @pull_request_review_comment = create(:pull_request_review_comment, pull_request: make_pull_request)
    @discussion_post             = create(:discussion_post)
    @discussion_post_reply       = create(:discussion_post_reply)

    @locked_issue.lock(@locked_issue.repository.owner)

    @blocked_user   = create(:user)
    @blocked_member = create(:user)
    @member         = create(:user)

    @discussion_post.team.add_member(@blocked_member)
    @discussion_post.team.add_member(@member)
    @discussion_post_reply.team.add_member(@blocked_member)
    @discussion_post_reply.team.add_member(@member)
  end

  context "label" do
    test "returns the label associated with the reaction's content" do
      reaction = build(:reaction, content: "smile")
      assert_equal "laugh", reaction.emotion.label
    end
  end

  context "emoji_character" do
    test "returns the emoji character that the reaction's content represents" do
      reaction = build(:reaction, content: "+1")
      assert_equal Emoji.find_by_alias("+1"), reaction.emotion.emoji_character
    end
  end

  context "Reaction.react" do
    test "creates reactions when they don't exist between subject and user" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))

      refute_predicate user.issue_comment_reactions, :any?

      reaction = issue_comment.react(actor: user, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.issue_comment_reactions.reload
      assert_same_elements [reaction], issue_comment.reactions.reload
    end

    test "creates reactions when user has permission to the subject via a team" do
      user = create(:user)
      org = create(:organization)
      team = create(:team, organization: org)
      team.add_member(user)
      repo = create(:private_repository)
      team.add_repository(repo, :pull, allow_different_owner: true)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))

      reaction = issue_comment.react(actor: user, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.issue_comment_reactions.reload
      assert_same_elements [reaction], issue_comment.reactions.reload
    end

    test "creates reactions when the subject's repository is a fork of the current repo (PR)" do
      user = forker = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org, from_example: :review_comment_source)

      forked = create(:fork_repository, forker: forker, fork_repo: repo, from_example: :review_comment_fork)

      commit_comment = create :commit_comment, user: forker, repository: forked, commit_id: "564af74a07da170ec3a45ef0a8cc34e8a8c1aa89"

      reaction = commit_comment.react(actor: user, content: "+1")

      assert_predicate reaction, :created?
      assert_same_elements [reaction], user.commit_comment_reactions.reload
      assert_same_elements [reaction], commit_comment.reactions.reload
    end

    test "does not create reactions when subjects are locked" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo)
      issue_comment = create(:issue_comment, issue: issue)

      issue.lock(user)

      reaction = T.let(nil, T.nilable(String))

      assert_no_difference "IssueCommentReaction.count" do
        reaction = issue_comment.react(actor: user, content: "+1")
      end

      refute_predicate reaction, :valid?
    end

    test "does not create reactions when user has no permission for a repository" do
      user = create(:user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: create(:private_repository)))

      reaction = T.let(nil, T.nilable(String))

      assert_no_difference "IssueCommentReaction.count" do
        reaction = issue_comment.react(actor: user, content: "+1")
      end

      refute_predicate reaction, :valid?
    end

    test "does not attempt to create reactions when the subject type is invalid" do
      user = create(:user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: create(:private_repository)))

      reaction = T.let(nil, T.nilable(String))

      assert_no_difference "Reaction.count" do
        reaction = Reaction.react(user: user, subject_id: user.id, subject_type: "User", content: "+1")
      end

      refute_predicate reaction, :valid?
    end

    test "is idempotent with respect to creating reactions" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))

      reaction = T.let(nil, T.nilable(String))
      repeated_reactions = []

      assert_difference "IssueCommentReaction.count", 1 do
        reaction = issue_comment.react(actor: user, content: "+1")
        repeated_reactions = [
          issue_comment.react(actor: user, content: "+1"),
          issue_comment.react(actor: user, content: "+1"),
        ]
      end

      assert_predicate reaction, :created?
      repeated_reactions.each { |r| assert_predicate r, :exists? }

      assert_same_elements [reaction], user.issue_comment_reactions.reload
      assert_same_elements [reaction], issue_comment.reactions.reload
    end

    test "does nothing when a reaction already exists between subject and user" do
      reaction = T.let(nil, T.nilable(IssueCommentReaction))
      returned_reaction = T.let(nil, T.nilable(IssueCommentReaction))

      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
      reaction = create(:issue_comment_reaction, issue_comment_id: issue_comment.id, user: user, content: "heart")

      assert_no_difference "IssueCommentReaction.count" do
        returned_reaction = reaction.subject.react(actor: reaction.user, content: reaction.content)
      end

      assert_predicate returned_reaction, :exists?
      assert_equal returned_reaction, reaction
    end

    test "does nothing when the unique database index is violated" do
      reaction = T.let(nil, T.nilable(IssueCommentReaction))
      returned_reaction = T.let(nil, T.nilable(IssueCommentReaction))

      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
      reaction = create(:issue_comment_reaction, issue_comment_id: issue_comment.id, user: user, content: "heart")

      IssueCommentReaction.stubs(:find_by).returns(nil)
      assert_no_difference "IssueCommentReaction.count" do
        returned_reaction = reaction.subject.react(actor: reaction.user, content: reaction.content)
      end

      assert_predicate returned_reaction, :exists?
      assert_equal returned_reaction, reaction
    end

    test "returns an invalid reaction when the content supplied is invalid" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))

      returned_reaction = T.let(nil, T.nilable(IssueCommentReaction))

      assert_no_difference "IssueCommentReaction.count" do
        returned_reaction = issue_comment.react(actor: user, content: "INVALID CONTENT")
      end

      refute_predicate returned_reaction, :valid?
      assert T.must(returned_reaction).errors.messages.keys.include?(:content), "reaction should be invalid because of its content"
    end

    if GitHub.interaction_limits_enabled?
      test "does not create reactions when repository interaction is not allowed" do
        user = create(:user)
        repo = create(:repository)
        issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:sockpuppet_disallowed, repo.owner, staff_actor: true)

        reaction = T.let(nil, T.nilable(String))

        assert_no_difference "IssueCommentReaction.count" do
          reaction = issue_comment.react(actor: user, content: "+1")
        end

        refute_predicate reaction, :valid?
      end
    end
  end

  context "Reaction.unreact" do
    test "destroys reactions between subject and user" do
      reaction = T.let(nil, T.nilable(IssueCommentReaction))
      destroyed_reaction = T.let(nil, T.nilable(IssueCommentReaction))

      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
      reaction = issue_comment.react(actor: user, content: "heart")

      assert_difference "IssueCommentReaction.count", -1 do
        destroyed_reaction = Reaction.unreact(user: reaction.user, subject_id: reaction.subject_id, subject_type: reaction.subject_type, content: reaction.content)
      end

      refute_predicate destroyed_reaction, :persisted?
    end

    test "is idempotent with respect to destroying reactions" do
      reaction = T.let(nil, T.nilable(IssueCommentReaction))
      other_reaction = T.let(nil, T.nilable(IssueCommentReaction))

      user = create(:user)
      repo = create(:repository, owner: user)
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
      reaction = issue_comment.react(actor: user, content: "heart")

      assert_difference "IssueCommentReaction.count", -1 do
        destroyed_reaction = Reaction.unreact(user: reaction.user, subject_id: reaction.subject_id, subject_type: reaction.subject_type, content: reaction.content)
        other_reaction = Reaction.unreact(user: destroyed_reaction.user, subject_id: destroyed_reaction.subject_id, subject_type: destroyed_reaction.subject_type, content: destroyed_reaction.content)
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
      issue_comment = create(:issue_comment, issue: create(:issue, repository: repo))
      reaction = issue_comment.react(actor: user, content: "+1")

      # User loses permission on the team that owns the private repo and the
      # subject:
      team.remove_member(user, force: true, send_notification: false)

      assert_no_difference "IssueCommentReaction.count" do
        Reaction.unreact(user: user, subject_id: issue_comment.id, subject_type: issue_comment.class.name, content: reaction.content)
      end
    end
  end

  context "Reaction.valid_subject?" do
    test "is true for a model that can be reacted to" do
      assert Reaction.valid_subject?(create(:issue_comment))
    end

    test "is false for a model that cannot be reacted to" do
      gist         = GistHelpers.generate(contents: [{ name: "1", value: "irrelevant file" }])
      gist_comment = gist.comments.create(body: "irrelevant comment", user: create(:user))

      refute Reaction.valid_subject?(gist_comment)
    end
  end

  context "Reaction.async_viewer_can_react?" do
    test "is true when issue unlocked" do
      assert Reaction.async_viewer_can_react?(create(:user), @issue).sync
    end

    test "is true for an unblocked user on an issue comment" do
      assert Reaction.async_viewer_can_react?(create(:user), @issue_comment).sync
    end

    test "is true for an unblocked user on a pr" do
      assert Reaction.async_viewer_can_react?(create(:user), @pull_request).sync
    end

    test "is true for an unblocked user on pr review" do
      assert Reaction.async_viewer_can_react?(create(:user), @pull_request_review_comment).sync
    end

    test "is true for an unblocked user on a discussion post" do
      assert Reaction.async_viewer_can_react?(@member, @discussion_post).sync
    end

    test "is true for an unblocked user on a discussion post reply" do
      assert Reaction.async_viewer_can_react?(@member, @discussion_post_reply).sync
    end

    test "is false when issue is locked" do
      refute Reaction.async_viewer_can_react?(create(:user), @locked_issue).sync
    end

    test "is false when blocked by the repo owner" do
      @issue.repository.owner.block(@blocked_user)
      refute Reaction.async_viewer_can_react?(@blocked_user, @issue).sync
    end

    test "is false when user is blocked by issue owner" do
      @issue.user.block(@blocked_user)
      refute Reaction.async_viewer_can_react?(@blocked_user, @issue).sync
    end

    test "is false when user is blocked by issue commenter" do
      @issue_comment.user.block(@blocked_user)
      refute Reaction.async_viewer_can_react?(@blocked_user, @issue_comment).sync
    end

    test "is false when user is blocked by pr owner" do
      @pull_request.user.block(@blocked_user)
      refute Reaction.async_viewer_can_react?(@blocked_user, @pull_request).sync
    end

    test "is false when user is blocked by pr review commenter" do
      @pull_request_review_comment.user.block(@blocked_user)
      refute Reaction.async_viewer_can_react?(@blocked_user, @pull_request_review_comment).sync
    end

    test "is false when user is blocked by discussion post user" do
      @discussion_post.user.block(@blocked_member)
      refute Reaction.async_viewer_can_react?(@blocked_member, @discussion_post).sync
    end

    test "is false when user is blocked by discussion post commenter" do
      @discussion_post_reply.user.block(@blocked_member)
      refute Reaction.async_viewer_can_react?(@blocked_member, @discussion_post_reply).sync
    end
  end

  context "Reaction::Status" do
    test "responds to created?" do
      reaction = Reaction::RecordStatus.new([Reaction.new, :invalid])
      refute_predicate reaction, :created?

      reaction = Reaction::RecordStatus.new([Reaction.new, :created])
      assert_predicate reaction, :created?
    end

    test "responds to exists?" do
      reaction = Reaction::RecordStatus.new([Reaction.new, :deleted])
      refute_predicate reaction, :exists?

      reaction = Reaction::RecordStatus.new([Reaction.new, :exists])
      assert_predicate reaction, :exists?
    end

    test "raises exception when passing invalid status" do
      reaction = Reaction.new
      assert_raises(ArgumentError, "Invalid status: erased") do
        Reaction::RecordStatus.new([reaction, :erased])
      end
    end
  end

  context "updating *Reaction tables" do
    test "reacting and unreacting to an CommitComment updates CommitCommentReactions" do
      assert_changes -> { CommitCommentReaction.count }, 1 do
        @commit_comment.react(actor: @member, content: "+1")
      end

      assert_changes -> { CommitCommentReaction.count }, -1 do
        @commit_comment.unreact(actor: @member, content: "+1")
      end
    end

    test "reacting and unreacting to an Issue updates IssueReactions" do
      assert_changes -> { IssueReaction.count }, 1 do
        @issue.react(actor: @member, content: "+1")
      end

      assert_changes -> { IssueReaction.count }, -1 do
        @issue.unreact(actor: @member, content: "+1")
      end
    end

    test "reacting and unreacting to an IssueComment updates IssueCommentReactions" do
      assert_changes -> { IssueCommentReaction.count }, 1 do
        @issue_comment.react(actor: @member, content: "+1")
      end

      assert_changes -> { IssueCommentReaction.count }, -1 do
        @issue_comment.unreact(actor: @member, content: "+1")
      end
    end

    test "reacting and unreacting to a PullRequestReview updates PullRequestReviewReactions" do
      assert_changes -> { PullRequestReviewReaction.count }, 1 do
        @pull_request_review.react(actor: @member, content: "+1")
      end

      assert_changes -> { PullRequestReviewReaction.count }, -1 do
        @pull_request_review.unreact(actor: @member, content: "+1")
      end
    end

    test "reacting and unreacting to a PullRequestReviewComment updates PullRequestReviewCommentReactions" do
      assert_changes -> { PullRequestReviewCommentReaction.count }, 1 do
        @pull_request_review_comment.react(actor: @member, content: "+1")
      end

      assert_changes -> { PullRequestReviewCommentReaction.count }, -1 do
        @pull_request_review_comment.unreact(actor: @member, content: "+1")
      end
    end

    test "legacy and new reaction types share the same ID" do
      legacy_issue_reaction = Reaction.react(user: @member, subject_id: @issue.id, subject_type: "Issue", content: "+1")
      new_issue_reaction = IssueReaction.where(user: @member, issue_id: @issue.id, content: "+1").first

      assert_equal legacy_issue_reaction.id, T.must(new_issue_reaction).id

      # Try that again because in the case above, both IDs would be 1 in a fresh database.
      # Now, `reactions` will get its second entry, `issue_comment_reactions` its first.
      legacy_issue_comment_reaction = Reaction.react(user: @member, subject_id: @issue_comment.id, subject_type: "IssueComment", content: "+1")
      new_issue_comment_reaction = IssueCommentReaction.where(user: @member, issue_comment_id: @issue_comment.id, content: "+1").first

      assert_equal legacy_issue_comment_reaction.id, T.must(new_issue_comment_reaction).id
    end
  end
end
