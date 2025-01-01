# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionEditTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true)
    @poll_category = @repo.discussion_categories.find_by(supports_polls: true)
  end

  test "discussion with its poll can be represented in an edit" do
    discussion = create(:discussion, body: "a" * MYSQL_UNICODE_BLOB_LIMIT, repository: @repo,
      category: @poll_category)
    poll = create(:discussion_poll, discussion: discussion, question: "a" * DiscussionPoll::MAX_QUESTION_LENGTH,
      option_texts: DiscussionPoll::MAX_OPTIONS.times.map { "a" * DiscussionPollOption::MAX_CHAR })
    diff = Discussion.body_with_poll(discussion.body, poll)

    edit = build(:discussion_edit, discussion: discussion, diff: diff)
    assert_predicate edit, :valid?, "edit should not have any validation errors"
    assert edit.save, "should have been able to persist the DiscussionEdit"
    assert_equal diff, edit.reload.diff, "should not have truncated diff"
  end
end
