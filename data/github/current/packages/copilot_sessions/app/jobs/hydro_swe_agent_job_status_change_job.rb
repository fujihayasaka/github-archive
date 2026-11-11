# typed: true
# frozen_string_literal: true

class HydroSweAgentJobStatusChangeJob < HydroMessageJob
  queue_as :hydro_swe_agent_job_status_change
  retry_on_dirty_exit

  METRIC_PREFIX = "hydro_swe_agent_job_status_change_job"

  sig { void }
  def perform
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

    # Denormalize the session lifecycle status onto the assignment. This is done
    # before the issue-resolution early returns below so the status stays correct
    # even when there is no notifiable issue subject. The write is race-safe and
    # uses the permissive LIVE policy (see AgentAssignmentStatus.apply_status!),
    # which allows a resumed session to move a terminal row back to :active.
    #
    # SEAM: a follow-up will add concurrency-counter decrement here, guarded by a
    # shared "terminal-event-processed" idempotency check so the same terminal
    # Hydro delivery can't decrement the counter twice. Do NOT add decrement logic
    # in this PR — it is owned by the counter/reconciliation work for
    # github/planning-tracking#3131. NOTE for that work: now that the live policy
    # permits completed -> active (resume / "un-finish"), the seam likely needs to
    # RE-INCREMENT the counter on a terminal -> active transition and decrement
    # again on the subsequent active -> terminal, without double-counting.
    denormalize_status(assignment)

    type = assignment.subject_type
    unless type == "issue"
      skip!("non_issue_subject")
      return
    end

    issue = assignment.subject
    unless issue
      skip!("missing_issue")
      return
    end

    # Trigger all viewers of Memex Projects with that Item to refetch the Item.
    issue.notify_socket_subscribers(associated_updates: { projects_updated: true })
    GitHub.dogstats.increment("#{METRIC_PREFIX}.updated.count", tags: telemetry_tags)
  end

  private

  # Maps the inbound lifecycle event to an AgentAssignment status and persists it
  # via the LIVE transition policy. No-ops when the event has no actionable status
  # or when the live policy disallows the transition (e.g. a duplicate terminal
  # event). The live policy is permissive: a resumed session may move a terminal
  # row back to :active.
  sig { params(assignment: AgentAssignment).void }
  def denormalize_status(assignment)
    new_status = CopilotSessions::AgentAssignmentStatus.from_hydro_event(topic, message)
    return unless new_status

    updated = with_write do
      CopilotSessions::AgentAssignmentStatus.apply_status!(
        assignment_id: assignment.id,
        target: new_status,
        policy: CopilotSessions::AgentAssignmentStatus::LIVE_EVENT
      )
    end

    return unless updated.positive?

    GitHub.dogstats.increment(
      "#{METRIC_PREFIX}.status_updated.count",
      tags: telemetry_tags + ["status:#{new_status}"]
    )
  end

  sig { params(reason: String).void }
  def skip!(reason)
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped.count", tags: telemetry_tags + ["reason:#{reason}"])
  end

  sig { returns(T::Array[String]) }
  def telemetry_tags
    ["topic:#{topic}"]
  end
end
