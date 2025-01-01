# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobileAssignedIssueTest < GitHub::TestCase
    test "#render" do
      issue = create(:issue)
      author = DummyAuthor.new
      event = create(:issue_event, event: "assigned")
      layout = AssignedIssueRenderer.new(issue: issue, author: author, event: event).render

      assert_equal "@john_doe assigned you", layout.title
      assert_equal "#{issue.repository.name_with_display_owner} ##{issue.number}", layout.subtitle
      assert_equal issue.body, layout.body
      assert_equal event.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal issue.permalink(include_host: false), layout.thread_id
      assert_equal "issue", layout.thread_type
    end
  end
end
