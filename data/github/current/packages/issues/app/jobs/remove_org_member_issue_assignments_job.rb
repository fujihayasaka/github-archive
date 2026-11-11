# typed: true
# frozen_string_literal: true

class RemoveOrgMemberIssueAssignmentsJob < RemoveOrgMemberDataJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :remove_org_member_issue_assignments

  REPO_BATCH_SIZE = 100
  ISSUE_BATCH_SIZE = 100

  # For a given user, goes through private org repositories that have
  # issue assignments for the user and are not pullable by the user and
  # removes the issue assignments.
  #
  # Saves a restorable archive of each cleared record before clearing.
  def perform(org, user, repo_offset_id = 0, issue_offset_id = 0, start_time = initially_enqueued_at)
    inaccessible_repo_ids = Repository.repo_ids_not_visible_to_user_from_orgs(user, [org.id], include_archived_repos: false)
    inaccessible_repo_ids.each_slice(ISSUE_BATCH_SIZE) do |repo_ids|
      Issue.throttle do
        issue_assignments_to_remove = all_issue_assignments(repo_ids).load # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        with_write do
          restorable.save_issue_assignments(issue_assignments_to_remove)
          remove_issue_assignments(issue_assignments_to_remove)
        end
      end
    end

    with_write { restorable.save_issue_assignments_complete }
    report_duration(start_time)
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

  sig { params(start_time: Time).void }
  def report_duration(start_time)
    duration = (Time.now - start_time) * 1_000
    GitHub.dogstats.distribution(
      "issues.remove_org_member_issue_assignments_job.dist.duration",
      duration)

  end
end
