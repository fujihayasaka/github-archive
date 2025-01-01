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
    if GitHub.esm_enabled? || org.feature_enabled?(:remove_org_member_issue_assignments_job_repo_optimization) ||
      org.business&.feature_enabled?(:remove_org_member_issue_assignments_job_repo_optimization)
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
      report_optimized_duration(start_time)
    else
      repo_batch, inaccessible_repo_ids = repos(repo_offset_id)
      issue_assignments_to_remove = issue_assignments(issue_offset_id, inaccessible_repo_ids)

      unless issue_assignments_to_remove.empty? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        with_write do
          restorable.save_issue_assignments(issue_assignments_to_remove)
          remove_issue_assignments(issue_assignments_to_remove)
        end
      end

      if done_processing?(repo_batch, issue_assignments_to_remove)
        with_write { restorable.save_issue_assignments_complete }
        report_duration(start_time)
      elsif maybe_more_issues?(issue_assignments_to_remove)
        RemoveOrgMemberIssueAssignmentsJob.perform_later \
          org, user, repo_offset_id, issue_assignments_to_remove.last.id, start_time
      else
        # maybe more repos
        RemoveOrgMemberIssueAssignmentsJob.perform_later \
          org, user, repo_batch.last.id, 0, start_time
      end
    end
  end

  private

  def done_processing?(repo_batch, issue_assignments_to_remove)
    repo_batch.size < REPO_BATCH_SIZE && issue_assignments_to_remove.size < ISSUE_BATCH_SIZE # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def maybe_more_issues?(issue_assignments_to_remove)
    issue_assignments_to_remove.size == ISSUE_BATCH_SIZE
  end

  def repos(repo_offset_id)
    repos_timer = Timer.start

    repo_batch = Repositories::Public.private_active_and_maintained_by_org(
      org_id: org.id,
      batch_start_id: repo_offset_id,
      batch_size: REPO_BATCH_SIZE
    )

    org_repos = inaccessible_org_repos(repo_batch)
    inaccessible_repo_ids = org_repos.collect(&:id)

    repos_timer.stop
    GitHub.dogstats.distribution("issues.remove_org_member_issue_assignments_job.dist.gather_repos_time", repos_timer.elapsed_ms)

    [repo_batch, inaccessible_repo_ids]
  end

  def all_issue_assignments(repositoriy_ids)
    return Issue.none if repositoriy_ids.empty?
    Issue.where(repository_id: repositoriy_ids)
      .assigned_to(user)
      .includes(:assignments)
      .order(:id)
  end

  def issue_assignments(issue_offset_id, inaccessible_repo_ids)
    return Issue.none if inaccessible_repo_ids.empty?
    Issue.where(repository_id: inaccessible_repo_ids)
      .assigned_to(user)
      .includes(:assignments)
      .where("issues.id > ?", issue_offset_id)
      .limit(ISSUE_BATCH_SIZE)
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
      duration,
      tags: ["optimized:false"])

  end

  sig { params(start_time: Time).void }
  def report_optimized_duration(start_time)
    duration = (Time.now - start_time) * 1_000
    GitHub.dogstats.distribution(
      "issues.remove_org_member_issue_assignments_job.dist.duration",
      duration,
      tags: ["optimized:true"])
  end
end
