# typed: true
# frozen_string_literal: true

class BulkRemoveOrgMemberIssueAssignmentsJob < ApplicationJob
  queue_as :bulk_remove_org_member_issue_assignments
  retry_on_dirty_exit

  ISSUE_BATCH_SIZE = 100

  attr_reader :user

  # For a given user, goes through private org repositories that have
  # issue assignments for the user and are not pullable by the user and
  # removes the issue assignments.
  #
  # Saves a restorable archive of each cleared record before clearing.
  def perform(organization_ids:, user_id:)
    @user = User.find_by(id: user_id)
    return if user.nil? || organization_ids.nil?

    inaccessible_repo_ids = Repository.repo_ids_not_visible_to_user_from_orgs(user, organization_ids, include_archived_repos: false)
    inaccessible_repo_ids.each_slice(ISSUE_BATCH_SIZE) do |repo_ids|
      Issue.throttle do
        issue_assignments_to_remove = all_issue_assignments(repo_ids)
        issue_assignments_to_remove = issue_assignments_to_remove.load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        with_write do
          remove_issue_assignments(issue_assignments_to_remove)
        end
      end
    end
  end

  private

  def all_issue_assignments(repositoriy_ids)
    return Issue.none if repositoriy_ids.empty?
    Issue.where(repository_id: repositoriy_ids)
      .assigned_to(user)
      .includes(:assignments)
      .order(:id)
  end

  def remove_issue_assignments(issue_assignments_to_remove)
    issue_assignments_to_remove.each do |issue|
      issue.remove_assignees(user)

      begin
        issue.throttle_with_retry { issue.save! }
      rescue ActiveRecord::ActiveRecordError => error
        Failbot.report(error)
      end
    end
  end
end
