# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentVoteTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:verified_user)
    @repo  = create(:repository, owner: @owner, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
    @comment = create(:discussion_comment, discussion: @discussion)
  end

  setup do
    User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(true))
  end

  context "scopes" do
    context "for_user" do
      test "returns votes for the specified user" do
        user = @discussion.user
        user_vote = create(:discussion_comment_vote, comment: @comment, user: user)
        not_user_vote = create(:discussion_comment_vote, comment: @comment, user: create(:verified_user))

        assert_includes DiscussionCommentVote.for_user(user), user_vote
        refute_includes DiscussionCommentVote.for_user(user), not_user_vote
      end
    end

    context "for_comment" do
      test "returns votes for the specified comment" do
        other_comment = create(:discussion_comment, discussion: @discussion)
        comment_vote = create(:discussion_comment_vote, comment: @comment)
        not_comment_vote = create(:discussion_comment_vote, comment: other_comment)

        assert_includes DiscussionCommentVote.for_comment(@comment), comment_vote
        refute_includes DiscussionCommentVote.for_comment(@comment), not_comment_vote
      end
    end

    context "for_discussion" do
      test "returns votes for the specified discussion" do
        other_comment = create(:discussion_comment)
        other_discussion = other_comment.discussion
        discussion_vote = create(:discussion_comment_vote, discussion: @discussion)
        not_discussion_vote = create(:discussion_comment_vote, discussion: other_discussion)

        assert_includes DiscussionCommentVote.for_discussion(@discussion), discussion_vote
        refute_includes DiscussionCommentVote.for_discussion(@discussion), not_discussion_vote
      end
    end
  end

  context "#deletable_by?" do
    test "true for the user who left the vote" do
      vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment)
      assert vote.deletable_by?(vote.user)
    end

    test "false for a user who did not leave the vote" do
      vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment)
      refute vote.deletable_by?(create(:verified_user))
    end
  end

  context "validations" do
    test "requires a user" do
      vote = DiscussionCommentVote.new
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "must exist"
    end

    test "requires a discussion" do
      vote = DiscussionCommentVote.new
      refute_predicate vote, :valid?
      assert_includes vote.errors[:discussion], "must exist"
    end

    test "requires user to have read access to the repository" do
      user = create(:verified_user)
      private_repo = create(:private_repository, has_discussions: true)
      private_discussion = create(:discussion, repository: private_repo)
      comment = create(:discussion_comment, discussion: private_discussion)
      vote = build(:discussion_comment_vote, discussion: private_discussion, comment: comment, user: user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be blocked by repo owner" do
      blocked_user = create(:verified_user, login: "blockeduser")
      @discussion.repository.owner.block(blocked_user)
      vote = build(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: blocked_user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be blocked by discussion author" do
      blocked_user = create(:verified_user, login: "blockeduser")
      @discussion.user.block(blocked_user)
      vote = build(:discussion_comment_vote,  comment: @comment, discussion: @discussion, user: blocked_user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be spammy" do
      vote = build(:discussion_comment_vote, comment: @comment, discussion: @discussion, user: create(:spammy_user, :verified))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end if GitHub.spamminess_check_enabled?

    test "requires user to not be suspended" do
      vote = build(:discussion_comment_vote, comment: @comment, discussion: @discussion, user: create(:suspended_user, :verified))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be blocked by comment author" do
      blocked_user = create(:verified_user, login: "blockeduser")
      @comment.user.block(blocked_user)
      vote = build(:discussion_comment_vote,  comment: @comment, discussion: @discussion, user: blocked_user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires discussion to be unlocked for non admins" do
      assert @discussion.lock(actor: @owner)

      vote = build(
        :discussion_comment_vote,
        comment: @comment,
        discussion: @discussion,
        user: @discussion.user,
      )

      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "does not require discussion to be unlocked for admins" do
      user = create(:verified_user)
      repo = create(:repository, owner: user, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      comment = create(:discussion_comment, discussion: discussion)
      discussion.lock(actor: user)

      vote = build(
        :discussion_comment_vote,
        comment: comment,
        discussion: discussion,
        user: user
      )

      assert_predicate vote, :valid?
    end

    test "requires repository interaction allowed" do
      User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))
      vote = build(:discussion_comment_vote, comment: @comment, discussion: @discussion)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    if GitHub.email_verification_enabled?
      test "requires user to have a verified email address" do
        vote = build(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: create(:user))
        refute_predicate vote, :valid?
        assert_includes vote.errors[:user], "can't vote at this time"
      end
    else
      test "does not require a user to have a verified email address" do
        vote = build(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: create(:user))
        assert_predicate vote, :valid?
      end
    end

    test "disallows the same user to vote twice on a comment" do
      orig_vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment)
      dupe_vote = build(:discussion_comment_vote, user: orig_vote.user, discussion: @discussion, comment: @comment)
      refute_predicate dupe_vote, :valid?
      assert_includes dupe_vote.errors[:comment], "has already received a vote from this user"
    end

    context "rate limits" do
      test "does not allow another vote when rate limit is exceeded" do
        enable_content_creation_rate_limiting
        limit = 2
        user = create(:verified_user)

        with_cache_enabled do
          Timecop.freeze do
            GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
              limit.times do
                vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: user)
                vote.delete
              end

              vote = build(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: user)

              refute vote.save
              assert_includes vote.errors.full_messages, GitHub::RateLimitedCreation::ERROR_MESSAGE
            end
          end
        end
      end
    end

    context "destroy validations" do
      test "non-admin cannot destroy a vote on a locked discussion" do
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: @discussion.user)
        @discussion.lock(actor: @owner)
        vote.reload # make sure the cached relationships are all updated

        assert_no_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "admin can destroy a vote on a locked discussion" do
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: @owner)
        @discussion.lock(actor: @owner)

        vote.reload # make sure the cached relationships are all updated

        assert_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert vote.errors[:user].empty?
      end

      test "requires repository interaction allowed" do
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: create(:verified_user))
        User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))

        assert_no_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be blocked by repo owner" do
        blocked_user = create(:verified_user, login: "blockeduser")
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: blocked_user)
        @discussion.repository.owner.block(blocked_user)

        assert_no_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be blocked by comment author" do
        blocked_user = create(:verified_user, login: "blockeduser")
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: blocked_user)
        @comment.user.block(blocked_user)

        assert_no_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be spammy" do
        spammer = create(:verified_user)
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: spammer)
        spammer.safer_mark_as_spammy

        assert_no_changes -> { DiscussionCommentVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end if GitHub.spamminess_check_enabled?

      test "requires user to not be suspended" do
        suspendee = create(:verified_user)
        vote = create(:discussion_comment_vote, discussion: @discussion, comment: @comment, user: suspendee)
        suspendee.suspend("test")

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end
    end
  end

  context "daily contributors count job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@discussion.repository.id, ts.to_date]) do
        create(:discussion_comment_vote, discussion: @discussion, comment: @comment, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      vote = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion_comment_vote, discussion: @discussion, comment: @comment, created_at: ts)
      end

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@discussion.repository.id, ts.to_date]) do
        vote.destroy
      end
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "logs event on creation" do
      travel_to Time.now do
        vote = create(:discussion_comment_vote, comment: @comment, upvote: true)
        message = {
          request_context: nil,
          comment: Hydro::EntitySerializer.discussion_comment(@comment),
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          repository: Hydro::EntitySerializer.repository(vote.repository),
          actor: Hydro::EntitySerializer.user(vote.user),
          upvote: true,
        }
        message_v2 = {
          repository_id: vote.repository.id,
          repository: Hydro::EntitySerializer.repository(vote.repository),
          repository_owner: Hydro::EntitySerializer.user(vote.repository.owner),
          discussion_comment_id: @comment.id,
          actor_id: vote.user.id,
          actor: Hydro::EntitySerializer.user(vote.user),
          action: :VOTE_ADDED,
          action_timestamp: Time.now
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentVoteCreate")
        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentVote")
      end
    end

    test "logs event on deletion" do
      travel_to Time.now do
        vote = create(:discussion_comment_vote, comment: @comment, upvote: true)
        vote.destroy
        message = {
          request_context: nil,
          comment: Hydro::EntitySerializer.discussion_comment(vote.comment),
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          repository: Hydro::EntitySerializer.repository(vote.repository),
          actor: Hydro::EntitySerializer.user(vote.user),
          upvote: true
        }
        message_v2 = {
          repository_id: vote.repository.id,
          repository: Hydro::EntitySerializer.repository(vote.repository),
          repository_owner: Hydro::EntitySerializer.user(vote.repository.owner),
          discussion_comment_id: @comment.id,
          actor_id: vote.user.id,
          actor: Hydro::EntitySerializer.user(vote.user),
          action: :VOTE_REMOVED,
          action_timestamp: Time.now
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCommentVoteDestroy")
        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsCommentVote")
      end
    end
  end
end
