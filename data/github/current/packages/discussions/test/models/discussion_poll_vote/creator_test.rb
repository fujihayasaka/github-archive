# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollVoteCreatorTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @other_user = create(:verified_user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @discussion = create(:discussion, repository: @repo, user: @user)
    @poll = create(:discussion_poll, discussion: @discussion)
    @poll_option, @other_poll_option = @poll.options
    @poll_vote = create(:discussion_poll_vote, poll: @poll, option: @poll_option, user: @other_user)
  end

  context "#create" do
    test "successfully adds a new vote to a poll" do
      assert_equal 1, @poll_option.votes.count
      vote = DiscussionPollVote::Creator.new(user: @user, option: @poll_option)
      assert vote.create
      assert_empty vote.errors
      assert_equal 2, @poll_option.votes.count
    end

    test "succeeds if user has already voted for an option" do
      assert_equal 1, @poll_option.votes.count
      vote = DiscussionPollVote::Creator.new(user: @other_user, option: @poll_option)
      assert vote.create
      assert_empty vote.errors
      assert_equal 1, @poll_option.votes.count
    end

    test "creates new vote for user who has already voted" do
      assert_equal 1, @poll_option.votes.count
      assert_equal 0, @other_poll_option.votes.count
      vote = DiscussionPollVote::Creator.new(user: @other_user, option: @other_poll_option)
      assert vote.create
      assert_empty vote.errors
      assert_equal 0, @poll_option.votes.count
      assert_equal 1, @other_poll_option.votes.count
    end

    test "requires user" do
      vote = DiscussionPollVote::Creator.new(user: nil, option: @poll_option)
      refute vote.create
      assert_equal ["User must exist"], vote.errors.full_messages
    end

    test "requires option" do
      vote = DiscussionPollVote::Creator.new(user: @user, option: nil)
      refute vote.create
      assert_equal ["Poll must exist", "Option must exist"], vote.errors.full_messages
    end

    test "returns error if discussion is locked" do
      @discussion.lock(actor: @user)
      assert_predicate @discussion, :locked?

      vote = DiscussionPollVote::Creator.new(user: @user, option: @poll_option)
      refute vote.create
      assert_equal ["Poll cannot be voted in because the discussion is locked"], vote.errors.full_messages
    end
  end
end
