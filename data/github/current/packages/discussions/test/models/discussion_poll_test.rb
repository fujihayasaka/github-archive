# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @author = create(:verified_user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org, has_discussions: true)
    @discussion = create(:discussion, repository: @repo, user: @author)
    @discussion_poll = create(:discussion_poll, discussion: @discussion)
    @discussion_poll_option, @discussion_poll_other_option = @discussion_poll.options
  end

  context "#to_s" do
    test "includes question and options" do
      expected = "#{@discussion_poll.question}\n\n- #{@discussion_poll_option.option}\n" \
        "- #{@discussion_poll_other_option.option}"
      assert_equal expected, @discussion_poll.to_s
    end
  end

  test "records are deleted when parent is deleted" do
    @discussion.destroy

    refute DiscussionPoll.find_by(id: @discussion_poll.id)
  end

  test "votes are deleted when parent is deleted" do
    create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option, user: @author)
    assert_difference(-> { DiscussionPollVote.count } => -1) do
      @discussion.destroy
    end
  end

  context "#has_voted?" do
    test "returns false if user is nil" do
      refute @discussion_poll.has_voted?(nil)
    end

    test "returns false if user has not voted" do
      refute @discussion_poll.has_voted?(@author)
    end

    test "returns true if user has voted" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option, user: @author)
      assert @discussion_poll.has_voted?(@author)
    end
  end

  context "constrains question length" do
    test "is valid if under limit" do
      poll = build(:discussion_poll, question: "Who is your favorite TWICE member?")
      assert_predicate poll, :valid?
    end

    test "is invalid if over limit" do
      limit = DiscussionPoll::MAX_QUESTION_LENGTH
      poll = build(:discussion_poll, question: "a" * (limit + 1))
      refute_predicate poll, :valid?
      assert_equal ["Question is too long (maximum is #{limit} characters)"], poll.errors.full_messages
    end

    test "blank question is invalid" do
      poll = build(:discussion_poll, question: "")
      refute_predicate poll, :valid?
      assert_equal ["Question can't be blank"], poll.errors.full_messages
    end
  end

  context "constrains number of options" do
    test "is invalid for one option" do
      new_poll = create(:discussion_poll, discussion: @discussion)
      new_poll.options = create_list(:discussion_poll_option, 1, poll: new_poll)

      refute new_poll.valid?
    end

    test "is invalid for 9 options" do
      new_poll = create(:discussion_poll, discussion: @discussion)
      new_poll.options = create_list(:discussion_poll_option, 9, poll: new_poll)

      refute new_poll.valid?
    end

    test "is valid for 4 options" do
      new_poll = create(:discussion_poll, discussion: @discussion)
      new_poll.options = create_list(:discussion_poll_option, 4, poll: new_poll)

      assert new_poll.valid?
    end
  end

  context "#reset_votes!" do
    test "resets votes" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)
      assert_equal 2, @discussion_poll.votes.count
      assert_equal 2, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_other_option.discussion_poll_votes_count

      assert @discussion_poll.reset_votes!

      assert_equal 0, @discussion_poll.reload.votes.count
      assert_equal 0, @discussion_poll.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_option.reload.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_other_option.reload.discussion_poll_votes_count
    end

    test "returns true if no votes exist" do
      assert_equal 0, @discussion_poll.votes.count
      assert @discussion_poll.reset_votes!
    end
  end

  context "resetting votes on change" do
    test "resets votes if question is changed" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      assert_equal 1, @discussion_poll.votes.count
      assert_equal 1, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count

      @discussion_poll.update!(question: "This is an updated question. Stan Dahyun!")

      assert_equal 0, @discussion_poll.reload.votes.count
      assert_equal 0, @discussion_poll.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_option.reload.discussion_poll_votes_count
    end

    test "does not reset votes if question does not change" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      assert_equal 1, @discussion_poll.votes.count
      assert_equal 1, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count

      @discussion_poll.touch

      assert_equal 1, @discussion_poll.reload.votes.count
      assert_equal 1, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.reload.discussion_poll_votes_count
    end
  end

  context "hydro v2" do
    test "logs event on creation" do
      discussion_poll = create(:discussion_poll, discussion: @discussion, actor: @author)
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository_id: @repo.id,
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        discussion_id: @discussion.id,
        discussion: Hydro::EntitySerializer.discussion(@discussion),
        actor_id: @author.id,
        actor: Hydro::EntitySerializer.user(@author),
        action: :ACTION_POLL_CREATED,
        action_timestamp: discussion_poll.created_at,
        poll_id: discussion_poll.id,
      }

      assert_hydro_published(message, schema: "github.discussions.v2.DiscussionsPoll")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsPoll")
    end

    test "logs event on update" do
      discussion_poll = create(:discussion_poll, discussion: @discussion, actor: @author)
      reset_hydro

      discussion_poll.update(question: "Should I change the question for this poll?")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository_id: @repo.id,
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
        discussion_id: @discussion.id,
        discussion: Hydro::EntitySerializer.discussion(@discussion),
        actor_id: @author.id,
        actor: Hydro::EntitySerializer.user(@author),
        action: :ACTION_POLL_UPDATED,
        action_timestamp: discussion_poll.updated_at,
        poll_id: discussion_poll.id,
      }

      assert_hydro_published(message, schema: "github.discussions.v2.DiscussionsPoll")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsPoll")
    end

    test "logs event on delete" do
      travel_to Time.now do
        discussion_poll = create(:discussion_poll, discussion: @discussion, actor: @author)
        reset_hydro
        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          discussion_id: @discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@discussion),
          actor_id: @author.id,
          actor: Hydro::EntitySerializer.user(@author),
          action: :ACTION_POLL_DELETED,
          action_timestamp: Time.now,
          poll_id: discussion_poll.id,
        }

        discussion_poll.destroy

        assert_hydro_published(message, schema: "github.discussions.v2.DiscussionsPoll")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.DiscussionsPoll")
      end
    end
  end
end
