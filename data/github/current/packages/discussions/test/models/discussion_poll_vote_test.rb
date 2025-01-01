# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollVoteTest < GitHub::TestCase
  fixtures do
    @author = create(:verified_user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org, has_discussions: true)
    @discussion = create(:discussion, repository: @repo, user: @author)
    @poll = create(:discussion_poll, discussion: @discussion)
    @poll_option = create(:discussion_poll_option, poll: @poll)
    @poll_vote = create(:discussion_poll_vote, poll: @poll, option: @poll_option, user: @author)
  end

  test "records are deleted when parent is deleted" do
    @poll_option.destroy

    refute DiscussionPollVote.find_by(id: @poll_vote.id)
  end

  context "validates that user has not voted on poll before" do
    test "errors if user voted before" do
      record = assert_raises(ActiveRecord::RecordInvalid) do
        create(:discussion_poll_vote, poll: @poll, option: @poll_option, user: @author)
      end
      assert_equal "Validation failed: User has already voted on this poll", record.message
    end

    test "does not error if user has not voted before" do
      new_user = create(:verified_user)
      assert_nothing_raised do
        create(:discussion_poll_vote, poll: @poll, option: @poll_option, user: new_user)
      end
    end
  end
end
