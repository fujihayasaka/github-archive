# typed: true
# frozen_string_literal: true

class HydroSweAgentJobStatusChangeJob < HydroMessageJob
  queue_as :hydro_swe_agent_job_status_change
  retry_on_dirty_exit

  METRIC_PREFIX = "hydro_swe_agent_job_status_change_job"

  sig { void }
  def perform
    unless FeatureFlag.vexi.enabled?(:memex_subscribe_copilot_task_updates, default: false)
      skip!("disabled")
      return
    end

    unless topic.in?([
      "github.copilot.v0.AgentSessionStart",
      "github.copilot.v0.AgentSessionStartPullRequest",
      "github.copilot.v0.AgentSessionFinish",
      "github.copilot.v0.AgentSessionFinishPullRequest",
      "github.copilot.v0.AgentSessionQueue",
      "github.copilot.v0.AgentSessionQueuePullRequest"
    ])
      skip!("unsupported_topic")
      return
    end

    task_id = message[:task_id].presence || message[:session_id].presence
    unless task_id.present?
      skip!("missing_task_id")
      return
    end

    repository_id = message[:repository_id]
    unless repository_id.present?
      skip!("missing_repository_id")
      return
    end

    # Link to the AgentAssignment to find the related Issue
    assignment = AgentAssignment.find_by(task_id: task_id, repository_id: repository_id)
    unless assignment
      skip!("no_assignment")
      return
    end

    unless assignment.source_type == "issue"
      skip!("non_issue_source")
      return
    end

    issue = assignment.source
    unless issue
      skip!("missing_issue")
      return
    end

    # Trigger all viewers of Memex Projects with that Item to refetch the Item.
    issue.notify_socket_subscribers(associated_updates: { projects_updated: true })
    GitHub.dogstats.increment("#{METRIC_PREFIX}.updated.count", tags: telemetry_tags)
  end

  private

  sig { params(reason: String).void }
  def skip!(reason)
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped.count", tags: telemetry_tags + ["reason:#{reason}"])
  end

  sig { returns(T::Array[String]) }
  def telemetry_tags
    ["topic:#{topic}"]
  end
end
