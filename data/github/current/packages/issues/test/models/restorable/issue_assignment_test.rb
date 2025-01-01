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

  test "issue assignments show up in search when user is restored to org" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    GitHub.flipper[:remove_org_member_repo_stars_job_use_bulk_ci_only].disable # This feature prevents creation of restorables
    GitHub.flipper[:members_without_2fa_allowed].disable
    @org.add_member @user

    # Assign private org issue to user
    repo = create(:private_repository, owner: @org)
    @issue = create(:assigned_issue, repository: repo, assignee: @user)

    # Ensure issue shows up in search results
    make_searchable @issue
    results = Search::Queries::IssueQuery.new(
      current_user: @user, phrase: "is:open is:issue assignee:#{@user}",
    ).execute
    assert_equal 1, results.total
    assert_equal @issue.id.to_s, results.first["_id"]

    # Enable 2FA enforcement on org
    only = [EnforceTwoFactorRequirementOnOrganizationJob, RemoveOrgMemberForksJob, RemoveOrgMemberIssueAssignmentsJob, RemoveOrgMemberRepositoryStarsJob, RemoveOrgMemberWatchedRepositoriesJob, RevokeOrgMembershipAbilitiesJob]
    perform_enqueued_jobs(only: only) do
      assert_difference "Restorable::OrganizationUser.count" do
        EnforceTwoFactorRequirementOnOrganizationJob.perform_later(@org, @org_admin)
      end
    end

    # Ensure issue no longer shows up in search results
    make_searchable @issue
    results = Search::Queries::IssueQuery.new(
      current_user: @user, phrase: "is:open is:issue assignee:#{@user}",
    ).execute
    assert_equal 0, results.total

    # Enable 2FA for user and restore user to org
    make_two_factor_credential(@user)
    org_user = Restorable::OrganizationUser.restorable(@org, @user)
    org_user.restore(actor: @org_admin)

    # Ensure issue shows up in search results again
    make_searchable @issue
    results = Search::Queries::IssueQuery.new(
      current_user: @user, phrase: "is:open is:issue assignee:#{@user}",
    ).execute
    assert_equal 1, results.total
    assert_equal @issue.id.to_s, results.first["_id"]
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
