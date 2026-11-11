# typed: true
# frozen_string_literal: true

# HydroCliSessionAgentAssignmentJob listens for AgentSessionStart events from
# copilot-mission-control and creates an AgentAssignment row when the session
# was attached by the CLI to an existing GitHub issue.
#
# This is the missing creator side of the planning-tracking#2952 vertical
# slice: copilot-mission-control sets event_type=cli_attached_issue plus
# event_identifiers=["issue::<number>"] on session create when the CLI
# attaches to an issue (copilot-mission-control#3311). The downstream
# HydroSweAgentJobStatusChangeJob already notifies socket subscribers for
# issue-typed AgentAssignments, but it expects an AgentAssignment to already
# exist. This job fills that gap.
#
# Idempotent: if an AgentAssignment already exists for the (task_id,
# subject_repository_id) pair, the job is a no-op.
class HydroCliSessionAgentAssignmentJob < HydroMessageJob
  queue_as :hydro_cli_session_agent_assignment
  retry_on_dirty_exit

  FEATURE_FLAG = :agent_assignment_from_cli_sessions
  METRIC_PREFIX = "hydro_cli_session_agent_assignment_job"
  CLI_ATTACHED_ISSUE_EVENT_TYPE = "cli_attached_issue"
  ISSUE_IDENTIFIER_PREFIX = "issue::"

  sig { void }
  def perform
    unless topic == "github.copilot.v0.AgentSessionStart"
      skip!("unsupported_topic")
      return
    end

    repository_id = message[:repository_id]
    unless repository_id.present?
      skip!("missing_repository_id")
      return
    end

    repository = Repository.find_by(id: repository_id)
    unless repository
      skip!("repository_not_found")
      return
    end

    unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, repository, default: false)
      skip!("feature_flag_disabled")
      return
    end

    task_id = message[:task_id].presence || message[:session_id].presence
    unless task_id.present?
      skip!("missing_task_id")
      return
    end

    event_type = message[:event_type].presence
    unless event_type == CLI_ATTACHED_ISSUE_EVENT_TYPE
      skip!("non_cli_attached_issue_event_type")
      return
    end

    issue_number = parse_issue_number(message[:event_identifiers])
    unless issue_number.present?
      skip!("missing_issue_identifier")
      return
    end

    if AgentAssignment.exists?(task_id: task_id, subject_repository_id: repository.id)
      skip!("assignment_already_exists")
      return
    end

    issue = repository.issues.find_by(number: issue_number)
    unless issue
      skip!("issue_not_found")
      return
    end

    # agent_id is a raw int64 on AgentSessionStart (not a wrapper). The cousin
    # HydroCopilotAgentAssignmentLiveUpdateJob consumes a different schema
    # (CopilotApiAgentSession) where agent_id IS wrapped, hence the different
    # access pattern. See proto definition at
    # github/hydro-schemas:proto/hydro/schemas/github/copilot/v0/agent_session_start.proto
    agent_integration_id = message[:agent_id]
    agent = agent_integration_id.present? && AgenticApp.agent_for_integration_id(agent_integration_id)
    unless agent
      skip!("agent_not_found")
      return
    end

    bot = Bot.find_by(id: agent.bot_id)
    unless bot
      skip!("bot_not_found")
      return
    end

    # user_id is a raw int64 on AgentSessionStart (not a wrapper), per the
    # proto definition cited above. Identifies the session creator who becomes
    # the AgentAssignment.assigner.
    user_id = message[:user_id]
    assigner = user_id.present? && User.find_by(id: user_id)
    unless assigner
      skip!("assigner_not_found")
      return
    end

    # v1: one active CLI session per (issue, creator). If the creator already
    # has an active CLI assignment on this issue, NOOP. First-write-wins so
    # a second `--issue` invocation doesn't double up the header pill while
    # the original session is still running. Scoped to the CLI bot
    # specifically so a parallel cloud-agent assignment on the same issue is
    # left untouched.
    #
    # "Active" = not in a terminal state. Today CLI assignments stay at
    # :pending forever because no producer transitions them (deferred idle
    # timeout, planning-tracking#2952). Including :active makes this
    # forward-compatible for when that lands.
    active_statuses = [
      AgentAssignment.statuses[:pending],
      AgentAssignment.statuses[:active],
    ]
    if AgentAssignment.exists?(
      subject_repository_id: repository.id,
      subject_type: AgentAssignment.subject_types[:issue],
      subject_id: issue.id,
      assigner_id: assigner.id,
      assignee_id: bot.id,
      status: active_statuses,
    )
      skip!("active_session_already_exists_for_issue")
      return
    end

    with_write do
      AgentAssignment.create!(
        subject_repository: repository,
        source_type: :issue,
        source_id: issue.id,
        subject_type: :issue,
        subject_id: issue.id,
        status: :pending,
        assignee: bot,
        assigner: assigner,
        task_id: task_id,
      )
    end

    GitHub.dogstats.increment("#{METRIC_PREFIX}.created.count", tags: telemetry_tags)
  rescue ActiveRecord::RecordNotUnique
    # Two AgentSessionStart events for the same session raced past the
    # exists? check above. The unique index on [task_id, repository_id]
    # (db/migrate/20260127194423_create_agent_assignments.rb) caught the
    # second writer; both events end with the assignment in place, so
    # this is safe to skip without retrying.
    skip!("assignment_created_concurrently")
  end

  private

  # event_identifiers carries entries in the form "issue::<number>" per the
  # convention established in copilot-mission-control/internal/session/origin.go.
  # Returns the numeric issue number as an integer, or nil if no usable
  # identifier is present. Only the first matching entry is honored.
  sig { params(identifiers: T.nilable(T::Array[String])).returns(T.nilable(Integer)) }
  def parse_issue_number(identifiers)
    return nil if identifiers.blank?

    identifiers.each do |id|
      next unless id.start_with?(ISSUE_IDENTIFIER_PREFIX)
      number = id.delete_prefix(ISSUE_IDENTIFIER_PREFIX).to_i
      return number if number > 0
    end

    nil
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
