# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/query_identifier_helper"

class IssueEventAuthorTest < GitHub::TestCase
  test "sets repository_id before validation" do
    issue_event_author = build(:issue_event_author)

    assert_nil issue_event_author.repository_id

    issue_event_author.valid?

    refute_nil issue_event_author.repository_id
  end

  if GitHub.spamminess_check_enabled?
    test "set up as spammable" do
      spammy_author = create(:user, spammy: true)
      issue_event_author = create(:issue_event_author, author: spammy_author)

      assert issue_event_author.spammy?
    end
  end
end
