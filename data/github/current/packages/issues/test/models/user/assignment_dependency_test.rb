# typed: true
# frozen_string_literal: true

require "test_helper"

class User::AssignmentDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  context "#assignable_to_issues?" do
    test "returns false for suspended user" do
      user = create :suspended_user
      assert_predicate user, :suspended?
      refute_predicate user, :assignable_to_issues?
    end

    test "returns true for non-spammy, non-suspended user" do
      user = User.new
      refute_predicate user, :suspended?
      refute_predicate user, :spammy?
      assert_predicate user, :assignable_to_issues?
    end
  end

  context "clear_issue_assignments" do
    test "logs info for debugging purposes when an error occurs" do
      user  = create(:user)
      repo  = create(:repository, owner: user)
      issue = create(:issue, repository: repo, assignee: user)
      IssueEvent
        .any_instance
        .stubs(:valid?)
        .returns(false)

      expected_logs = {
        "Body": "clear_issue_assignments.issue.save.fail",
        "gh.issue.id": issue.id,
        "gh.actor.id": user.id,
        "gh.issue.event.name": issue.events.first.event,
        "gh.repo.id": repo.id,
      }
      assert_logged **expected_logs do
        user.clear_issue_assignments
      end
    end

    test "clears a user's assignments from all of their repositories" do
      user   = create(:user)
      repo   = create(:repository, owner: user)
      issues = Array.new(2) { create(:issue, repository: repo, assignee: user) }

      user.clear_issue_assignments

      issues.each do |issue|
        issue.reload
        refute_includes issue.assignees, user
      end
    end

    test "can be restricted to a scope" do
      user               = create(:user)
      in_scope_repo      = create(:repository, owner: user, name: "in-scope")
      in_scope_issue     = create(:issue, repository: in_scope_repo, assignee: user)
      out_of_scope_repo  = create(:repository, owner: user, name: "out-of-scope")
      out_of_scope_issue = create(:issue, repository: out_of_scope_repo, assignee: user)

      user.clear_issue_assignments(scope: in_scope_repo.issues)

      in_scope_issue.reload
      refute_includes in_scope_issue.assignees, user

      out_of_scope_issue.reload
      assert_includes out_of_scope_issue.assignees, user
    end
  end
end
