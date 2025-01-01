# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobileIssueTest < GitHub::TestCase
    test "#render" do
      issue = create(:issue)
      author = DummyAuthor.new
      layout = IssueRenderer.new(issue: issue, author: author).render

      assert_equal "@john_doe mentioned you", layout.title
      assert_equal "#{issue.repository.name_with_display_owner} ##{issue.number}", layout.subtitle
      assert_equal issue.body, layout.body
      assert_equal issue.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal issue.permalink(include_host: false), layout.thread_id
      assert_equal "issue", layout.thread_type
    end
  end
end
