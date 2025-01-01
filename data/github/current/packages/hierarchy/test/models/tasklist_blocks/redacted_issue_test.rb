# typed: true
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class RedactedIssueTest < GitHub::TestCase
    test "accessors" do
      redacted_issue = TasklistBlocks::RedactedIssue.new(position: 100)

      assert_equal "00000000-0000-0000-0000-000000000000", redacted_issue.key.primaryKey.uuid
      assert_equal 0, redacted_issue.key.ownerId
      assert_equal 0, redacted_issue.key.itemId
      assert_equal "You can't see this item", redacted_issue.title
      assert_equal "", redacted_issue.url
      assert_equal "draft", redacted_issue.state
      assert_equal "", redacted_issue.stateReason
      assert_equal 0, redacted_issue.number
      assert_equal 0, redacted_issue.repoId
      assert_equal "", redacted_issue.repoName
      assert_equal "", redacted_issue.userName
    end

    test "has title if provided" do
      redacted_issue = TasklistBlocks::RedactedIssue.new(position: 100, title: "http://some-url-for-hidden-issue.com")

      assert_equal "http://some-url-for-hidden-issue.com", redacted_issue.title
    end
  end
end
