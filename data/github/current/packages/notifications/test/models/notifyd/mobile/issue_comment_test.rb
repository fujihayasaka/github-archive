# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./dummy_author"

module Notifyd::Mobile
  class MobileIssueCommentTest < GitHub::TestCase
    test "#render" do
      issue_comment = create(:issue_comment)
      author = DummyAuthor.new
      layout = IssueCommentRenderer.new(
        issue_comment: issue_comment,
        issue: T.must(issue_comment.issue),
        author: author
      ).render

      assert_equal "@john_doe mentioned you", layout.title
      assert_equal "#{issue_comment.issue.repository.name_with_display_owner} ##{issue_comment.issue.number}", layout.subtitle
      assert_equal issue_comment.body, layout.body
      assert_equal issue_comment.permalink, layout.url
      assert_equal author.avatar_url, layout.avatar_url
      assert_equal author.profile_name, layout.author_profile_name
      assert_equal author.username, layout.author_username
      assert_equal issue_comment.issue.permalink(include_host: false), layout.thread_id
      assert_equal "issue", layout.thread_type
    end
  end
end
