# typed: true
# frozen_string_literal: true

class NullifyMilestoneIdReferencesJob < ApplicationJob
  queue_as :nullify_milestone_id_references
  retry_on_dirty_exit

  BATCH_SIZE = 1_000

  def perform(old_milestone_id, old_milestone_title, actor_id, create_demilestoned_events: true, issue_id_offset: 1, repository_id: nil)
    # We expect this job only to be called after the milestone has been destroyed.
    if Milestone.where(id: old_milestone_id).exists?
      GitHub.dogstats.increment("job.nullify_milestone_id_references.milestone_still_exists")
      return
    end

    milestone_issues_query = Issue.where(milestone_id: old_milestone_id)
        .where("id >= ?", issue_id_offset)

    milestone_issues_query = if repository_id
      milestone_issues_query.where(repository_id: repository_id)
    else
      milestone_issues_query
    end

    milestone_issues = milestone_issues_query
      .order(id: :asc)
      .limit(BATCH_SIZE + 1)
      .all
      .to_a

    return if milestone_issues.empty?

    next_milestone_issue = milestone_issues.length > BATCH_SIZE ? milestone_issues.pop : nil
    actor = User.find_by(id: actor_id) || User.ghost

    milestone_issues.each do |issue|
      issue.throttle_writes do
        next if issue.repository.nil?

        Issue.transaction do
          if create_demilestoned_events && issue.open?
            issue.events.create(
              event: "demilestoned",
              actor: actor,
              milestone_title: old_milestone_title,
              skip_hydro_event_instrumentation: true
            )
          end
          issue.update(milestone_id: nil)
        end
      end
    end

    if next_milestone_issue
      NullifyMilestoneIdReferencesJob.perform_later(
        old_milestone_id,
        old_milestone_title,
        actor_id,
        create_demilestoned_events: create_demilestoned_events,
        issue_id_offset: next_milestone_issue.id,
        repository_id: repository_id
      )
    end
  end
end
