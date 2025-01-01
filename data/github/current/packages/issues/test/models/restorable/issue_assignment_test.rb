# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableIssueAssignmentTest < GitHub::TestCase
  fixtures do
    setup_search

    @user = create(:user)
    @org_admin = create(:two_factor_credential_user)
    @org = create(:organization, admin: @org_admin)
    @repo = create(:repository, owner: @org)
    @issue = create(:issue, repository: @repo, user: @user)
    @restorable = Restorable.create
  end

  setup do
    # Allow the fake test cache to store the job state.
    GitHub.cache.allow = /enforce-two-factor-requirement-on-organization/
  end

  teardown_once do
    teardown_search
  end

  test ".restore assigns user to issue" do
    refute_includes @issue.assignees, @user

    @restorable.issue_assignments.create(issue_id: @issue.id)
    @restorable.saved(:restorable_issue_assignments)
    @org.add_member(@user)
    Restorable::IssueAssignment.restore(
      restorable: @restorable,
      user: @user
    )

    assert_includes @issue.reload.assignees, @user
  end

  test ".restore does not attempt to restore if subject has been deleted" do
    @restorable.issue_assignments.create(issue_id: @issue.id)
    @restorable.saved(:restorable_issue_assignments)
    @issue.delete
    Restorable::IssueAssignment.restore(
      restorable: @restorable,
      user: @user
    )

    Issue.expects(:assignees).never
  end

  test ".restore does not bomb when called more than once" do
    @restorable.issue_assignments.create(issue_id: @issue.id)
    Restorable::IssueAssignment.restore(
      restorable: @restorable,
      user: @user
    )
    Restorable::IssueAssignment.restore(
      restorable: @restorable,
      user: @user
    )
  end
end
