# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollOptionTest < GitHub::TestCase
  fixtures do
    @author = create(:verified_user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org, has_discussions: true)
    @discussion = create(:discussion, repository: @repo, user: @author)
    @discussion_poll = create(:discussion_poll, discussion: @discussion)
    @discussion_poll_option = create(:discussion_poll_option, poll: @discussion_poll)
    @discussion_poll_other_option = create(:discussion_poll_option, poll: @discussion_poll)
    @other_discussion_poll_option = create(:discussion_poll_option, poll: @discussion_poll)
  end

  context "#to_s" do
    test "returns value of 'option' field" do
      poll_option = DiscussionPollOption.new(option: "foo bar")
      assert_equal "foo bar", poll_option.to_s
    end
  end

  test "records are deleted when parent is deleted" do
    @discussion_poll.destroy

    refute DiscussionPollOption.find_by(id: @discussion_poll_option.id)
  end

  test "is valid when character length is up to 128" do
    @discussion_poll_option.update(option: "There’s always a bigger fish.")

    assert @discussion_poll_option.valid?
  end

  test "is invalid when character length is less than 1" do
    @discussion_poll_option.update(option: "")

    refute @discussion_poll_option.valid?
  end

  test "is invalid when character length is greater than 128" do
    @discussion_poll_option.update(option: "You were the Chosen One! It was said that you would destroy the Sith, not join them. bring balance to the force, not leave it in darkness.")

    refute @discussion_poll_option.valid?
  end

  context "resetting votes" do
    test "deletes all votes and sets counters to zero when option is updated" do
      vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      other_vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)
      assert_equal 2, @discussion_poll.votes.count
      assert_equal 2, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_other_option.discussion_poll_votes_count

      @discussion_poll_option.update!(option: "stan dahyun")

      assert_equal 0, @discussion_poll.reload.votes.count
      assert_equal 0, @discussion_poll.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_option.reload.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_other_option.reload.discussion_poll_votes_count
    end

    test "adding a vote does not reset votes" do
      vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      other_vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)
      assert_equal 2, @discussion_poll.votes.count
      assert_equal 2, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_other_option.discussion_poll_votes_count

      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)

      assert_equal 3, @discussion_poll.votes.count
      assert_equal 3, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 2, @discussion_poll_other_option.discussion_poll_votes_count
    end

    test "deletes all votes and sets counters to zero when new option is added to poll" do
      vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      other_vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)
      assert_equal 2, @discussion_poll.votes.count
      assert_equal 2, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_other_option.discussion_poll_votes_count

      create(:discussion_poll_option, poll: @discussion_poll)

      assert_equal 0, @discussion_poll.reload.votes.count
      assert_equal 0, @discussion_poll.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_option.reload.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_other_option.reload.discussion_poll_votes_count
    end

    test "deletes all votes and sets counters to zero when new option is removed from poll" do
      vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option)
      other_vote = create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_other_option)
      assert_equal 2, @discussion_poll.votes.count
      assert_equal 2, @discussion_poll.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_option.discussion_poll_votes_count
      assert_equal 1, @discussion_poll_other_option.discussion_poll_votes_count

      @discussion_poll_other_option.destroy!

      assert_equal 0, @discussion_poll.reload.votes.count
      assert_equal 0, @discussion_poll.discussion_poll_votes_count
      assert_equal 0, @discussion_poll_option.reload.discussion_poll_votes_count
    end
  end

  context "#has_voted?" do
    test "returns false if user is nil" do
      refute @discussion_poll_option.has_voted?(nil)
    end

    test "returns false if user has not voted for this option" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @other_discussion_poll_option, user: @author)
      refute @discussion_poll_option.has_voted?(@author)
    end

    test "returns true if user has voted for this option" do
      create(:discussion_poll_vote, poll: @discussion_poll, option: @discussion_poll_option, user: @author)
      assert @discussion_poll_option.has_voted?(@author)
    end
  end
end
