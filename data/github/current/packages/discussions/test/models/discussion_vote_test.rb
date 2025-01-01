# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionVoteTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:verified_user)
    @repo = create(:repository, owner: @owner, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
    User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(true))
  end

  context ".update_votes_counts" do
    test "enqueues job to update discussion search index" do
      Search.expects(:add_to_search_index).once.with("discussion", @discussion.id)
      DiscussionVote.update_votes_counts(@discussion.id)
    end

    test "updates total_upvotes on specified discussion based on existing upvote records" do
      @discussion.update_attribute(:total_upvotes, 200)
      actual_value = @discussion.upvotes.count
      refute_equal 200, actual_value

      DiscussionVote.update_votes_counts(@discussion.id)

      assert_equal actual_value, @discussion.reload.total_upvotes
    end

    test "does not enqueue job to update search index when no discussion is updated" do
      @discussion.delete
      Search.expects(:add_to_search_index).with("discussion", @discussion.id).never
      DiscussionVote.update_votes_counts(@discussion.id)
    end
  end

  context "#deletable_by?" do
    test "true for the user who left the vote" do
      vote = create(:discussion_vote, discussion: @discussion)
      assert vote.deletable_by?(vote.user)
    end

    test "false for a user who did not leave the vote" do
      vote = create(:discussion_vote, discussion: @discussion)
      refute vote.deletable_by?(create(:verified_user))
    end
  end

  context "validations" do
    test "requires a user" do
      vote = DiscussionVote.new
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "must exist"
    end

    test "requires a discussion" do
      vote = DiscussionVote.new
      refute_predicate vote, :valid?
      assert_includes vote.errors[:discussion], "must exist"
    end

    test "requires user to have read access to the repository" do
      private_repo = create(:private_repository, has_discussions: true)
      private_discussion = create(:discussion, repository: private_repo)
      vote = build(:discussion_vote, discussion: private_discussion, user: create(:verified_user))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be blocked by repo owner" do
      blocked_user = create(:verified_user, login: "blockeduser")
      @discussion.repository.owner.block(blocked_user)
      vote = build(:discussion_vote, discussion: @discussion, user: blocked_user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be blocked by discussion author" do
      blocked_user = create(:verified_user, login: "blockeduser")
      @discussion.user.block(blocked_user)
      vote = build(:discussion_vote, discussion: @discussion, user: blocked_user)
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires user to not be spammy" do
      vote = build(:discussion_vote, discussion: @discussion, user: create(:spammy_user, :verified))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end if GitHub.spamminess_check_enabled?

    test "requires user to not be suspended" do
      vote = build(:discussion_vote, discussion: @discussion, user: create(:suspended_user, :verified))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "requires discussion to be unlocked for non admins" do
      @discussion.lock(actor: @owner)
      vote = build(:discussion_vote, discussion: @discussion, user: create(:verified_user))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    test "does not require discussion to be unlocked for admins" do
      user = create(:verified_user)
      repo = create(:repository, owner: user, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      discussion.lock(actor: user)

      vote = build(:discussion_vote, discussion: discussion, user: user)

      assert_predicate vote, :valid?
    end

    test "requires repository interaction allowed" do
      User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))
      vote = build(:discussion_vote, discussion: @discussion, user: create(:verified_user))
      refute_predicate vote, :valid?
      assert_includes vote.errors[:user], "can't vote at this time"
    end

    if GitHub.email_verification_enabled?
      test "requires user to have a verified email address" do
        vote = build(:discussion_vote, discussion: @discussion, user: create(:user))
        refute_predicate vote, :valid?
        assert_includes vote.errors[:user], "can't vote at this time"
      end
    else
      test "does not require a user to have a verified email address" do
        vote = build(:discussion_vote, discussion: @discussion, user: create(:user))
        assert_predicate vote, :valid?
      end
    end

    test "disallows the same user to vote twice on a discussion" do
      orig_vote = create(:discussion_vote, discussion: @discussion)
      dupe_vote = build(:discussion_vote, user: orig_vote.user, discussion: @discussion)
      refute_predicate dupe_vote, :valid?
      assert_includes dupe_vote.errors[:discussion], "has already received a vote from this user"
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
                vote = create(:discussion_vote, user: user, discussion: @discussion)
                vote.delete
              end

              vote = build(:discussion_vote, user: user, discussion: @discussion)

              refute vote.save
              assert_includes vote.errors.full_messages, GitHub::RateLimitedCreation::ERROR_MESSAGE
            end
          end
        end
      end
    end

    context "destroy validations" do
      test "non-admin cannot destroy a vote on a locked discussion" do
        vote = create(:discussion_vote, discussion: @discussion, user: create(:verified_user))
        @discussion.lock(actor: @owner)

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "admin can destroy a vote on a locked discussion" do
        vote = create(:discussion_vote, discussion: @discussion, user: @owner)
        @discussion.lock(actor: @owner)

        assert_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert vote.errors[:user].empty?
      end

      test "requires repository interaction allowed" do
        vote = create(:discussion_vote, discussion: @discussion, user: create(:verified_user))
        User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be blocked by repo owner" do
        blocked_user = create(:verified_user, login: "blockeduser")
        vote = create(:discussion_vote, discussion: @discussion, user: blocked_user)
        @discussion.repository.owner.block(blocked_user)

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be blocked by discussion author" do
        blocked_user = create(:verified_user, login: "blockeduser")
        vote = create(:discussion_vote, discussion: @discussion, user: blocked_user)
        @discussion.user.block(blocked_user)

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end

      test "requires user to not be spammy" do
        spammer = create(:verified_user)
        vote = create(:discussion_vote, discussion: @discussion, user: spammer)
        spammer.safer_mark_as_spammy

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end if GitHub.spamminess_check_enabled?

      test "requires user to not be suspended" do
        suspendee = create(:verified_user)
        vote = create(:discussion_vote, discussion: @discussion, user: suspendee)
        suspendee.suspend("test")

        assert_no_changes -> { DiscussionVote.count } do
          vote.destroy
        end
        assert_includes vote.errors[:user], "can't vote at this time"
      end
    end
  end

  context "discussions daily contributors job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@discussion.repository.id, ts.to_date]) do
        create(:discussion_vote, discussion: @discussion, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")

      vote = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion_vote, discussion: @discussion, created_at: ts)
      end

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@discussion.repository.id, ts.to_date]) do
        vote.destroy
      end
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "logs event on creation" do
      travel_to Time.now do
        vote = create(:discussion_vote, upvote: true)
        message = {
          request_context: nil,
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          repository: Hydro::EntitySerializer.repository(vote.repository),
          actor: Hydro::EntitySerializer.user(vote.user),
          upvote: true,
        }

        message_v2 = {
          repository_id: vote.repository.id,
          repository: Hydro::EntitySerializer.repository(vote.repository),
          discussion_id: vote.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          actor_id: vote.user.id,
          actor: Hydro::EntitySerializer.user(vote.user),
          action: :VOTE_ADDED,
          action_timestamp: vote.created_at
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionVoteCreate")
        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsVote")
      end
    end

    test "logs event on deletion" do
      travel_to Time.now do
        vote = create(:discussion_vote, upvote: true)
        vote.destroy
        message = {
          request_context: nil,
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          repository: Hydro::EntitySerializer.repository(vote.repository),
          actor: Hydro::EntitySerializer.user(vote.user),
          upvote: true,
        }
        message_v2 = {
          repository_id: vote.repository.id,
          repository: Hydro::EntitySerializer.repository(vote.repository),
          discussion_id: vote.discussion.id,
          discussion: Hydro::EntitySerializer.discussion(vote.discussion),
          actor_id: vote.user.id,
          actor: Hydro::EntitySerializer.user(vote.user),
          action: :VOTE_REMOVED,
          action_timestamp: Time.now
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionVoteDestroy")
        assert_hydro_published(message_v2, schema: "github.discussions.v2.DiscussionsVote")
      end
    end
  end
end
