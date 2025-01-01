# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobileDiscussionCommentTest < GitHub::TestCase
    test "#render" do
      discussion_comment = create(:discussion_comment)
      author = DummyAuthor.new
      layout = DiscussionCommentRenderer.new(
        discussion_comment: discussion_comment,
        discussion: T.must(discussion_comment.discussion),
        author: author
      ).render

      assert_equal "@john_doe mentioned you", layout.title
      assert_equal "#{discussion_comment.repository.name_with_display_owner} ##{discussion_comment.discussion.number}", layout.subtitle
      assert_equal discussion_comment.body, layout.body
      assert_equal discussion_comment.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal discussion_comment.discussion.permalink(include_host: false), layout.thread_id
      assert_equal "discussion", layout.thread_type
    end
  end
end
