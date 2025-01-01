# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueConvertToIssueDepdendencyTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @repo = create(:repository, owner: @org)
  end

  test "updates the issue body with the newly created issue" do
    parent_issue = create(:issue, repository: @repo, user: @admin, body: <<~MD)
    - [ ] This is our target
    - [ ] item 2
      MD

    child_issue = create(:issue, repository: @repo, user: @admin)
    updated = parent_issue.update_issue_body_after_convert_task([0, 0], child_issue, @admin)

    assert updated

    assert_match /- \[ \] ##{child_issue.number}/, parent_issue.body
    refute_match /- \[ \] This is our target/, parent_issue.body
  end

  test "updates the issue body with the newly created issue - different list / position" do
    parent_issue = create(:issue, repository: @repo, user: @admin, body: <<~MD)
    - [ ] Item 1
    - [ ] item 2

    Test

    - [ ] item 1
      - [ ] Item 2
      - [ ] This is our target
    - [ ] Item 5
      - [ ] Item 6
      MD

    child_issue = create(:issue, repository: @repo, user: @admin)
    updated = parent_issue.update_issue_body_after_convert_task([2, 1], child_issue, @admin)

    assert updated

    assert_match /- \[ \] ##{child_issue.number}/, parent_issue.body
    refute_match /- \[ \] This is our target/, parent_issue.body
  end

  test "returns false if the list isn't found" do
    parent_issue = create(:issue, repository: @repo, user: @admin, body: <<~MD)
    - [ ] Item 1
    - [ ] item 2

    Test

    No other lists
      MD

    child_issue = create(:issue, repository: @repo, user: @admin)
    updated = parent_issue.update_issue_body_after_convert_task([2, 1], child_issue, @admin)

    refute updated
  end

  test "rreturns false if the position argument is incorrect" do
    parent_issue = create(:issue, repository: @repo, user: @admin, body: <<~MD)
    - [ ] Item 1
    - [ ] item 2

    Test

    No other lists
      MD

    child_issue = create(:issue, repository: @repo, user: @admin)

    refute parent_issue.update_issue_body_after_convert_task([2], child_issue, @admin)
  end

  test "returns false if the position argument contains a negative" do
    parent_issue = create(:issue, repository: @repo, user: @admin, body: <<~MD)
    - [ ] Item 1
    - [ ] item 2

    Test

    No other lists
      MD

    child_issue = create(:issue, repository: @repo, user: @admin)

    refute parent_issue.update_issue_body_after_convert_task([2, -1], child_issue, @admin)
  end
end
