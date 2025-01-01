# typed: false
# frozen_string_literal: true

class ResyncProjectWorkflowsJob < ApplicationJob
  # Use primary connection for writing data to projects, project_workflows tables.
  use_primaries ApplicationRecord::Mysql1,
  # Use primary connection for writing data to key_values table.
  ApplicationRecord::Mysql5

  class ResyncError < StandardError; end

  retry_on_dirty_exit

  queue_as :project_workflow_resync

  def perform(project_id, arguments = {})
    start = Time.current
    actor_id, queued_at, status_id = arguments.with_indifferent_access.values_at("actor_id", "queued_at", "status_id")
    queued_at = queued_at.is_a?(String) ? Time.parse(queued_at) : queued_at

    status = JobStatus.find(status_id)
    unless status
      GitHub.dogstats.increment("job.resync_project_workflows.missing_status")
      return
    end

    status.track do
      GitHub.dogstats.timing_since "job.resync_project_workflows.time_enqueued", queued_at

      project = Project.find_by_id(project_id)
      unless project
        GitHub.dogstats.increment("job.resync_project_workflows.unknown_project")
        return
      end

      actor = User.find_by_id(actor_id)
      unless actor
        GitHub.dogstats.increment("job.resync_project_workflows.unknown_actor")
        return
      end

      project.resync_workflows!(actor: actor, as_of: queued_at)
    end
  rescue ActiveRecord::ActiveRecordError => e
    Failbot.report(ResyncError.new("project_id: #{project_id}"), app: "github-projects")
  ensure
    GitHub.dogstats.timing_since "job.resync_project_workflows.time", start
  end
end
