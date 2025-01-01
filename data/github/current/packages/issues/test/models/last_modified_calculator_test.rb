# typed: true
# frozen_string_literal: true

require "test_helper"

class LastModifiedCalculationTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue)
    comment = create :issue_comment, issue: @issue
    comment2 = create :issue_comment, issue: @issue
  end

  test "last_modified_with" do
    assignee = create(:user)
    @issue.repository.add_member(assignee)
    @issue.assignee = assignee

    @issue.updated_at = Time.utc(2011)
    @issue.assignee.updated_at = Time.utc(2012)
    @issue.user.updated_at = Time.utc(2013)

    assert_equal Time.utc(2013), @issue.last_modified_with(:assignee, :user)
    assert_equal Time.utc(2012), @issue.last_modified_with(:assignee)
    assert_equal Time.utc(2011), @issue.last_modified_with
  end

  test "last_modified_from" do
    user = User.new
    user.updated_at = Time.utc(2013).in_time_zone

    assert_equal Time.utc(2013).in_time_zone, T.unsafe(user).last_modified_from(
      [Time.utc(2011).in_time_zone, user])
  end
end
