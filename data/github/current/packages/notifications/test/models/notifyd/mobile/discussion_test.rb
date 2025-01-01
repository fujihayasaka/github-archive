# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobileDiscussionTest < GitHub::TestCase
    test "#render" do
      discussion = create(:discussion)
      author = DummyAuthor.new
      layout = DiscussionRenderer.new(discussion: discussion, author: author).render

      assert_equal "@john_doe mentioned you", layout.title
      assert_equal "#{discussion.repository.name_with_display_owner} ##{discussion.number}", layout.subtitle
      assert_equal discussion.body, layout.body
      assert_equal discussion.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal discussion.permalink(include_host: false), layout.thread_id
      assert_equal "discussion", layout.thread_type
    end
  end
end
