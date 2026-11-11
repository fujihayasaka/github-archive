# typed: true
# frozen_string_literal: true

# HydroSweAgentCloseReferenceJob listens for AgentSessionStartPullRequest and AgentSessionPullRequestCreated
# events with an event_type of "issues_agent_assignment" and creates a close issue reference from the PR to the target issue
class HydroSweAgentCloseReferenceJob < HydroMessageJob
  queue_as :hydro_swe_agent_close_reference
  retry_on_dirty_exit

  resolve_tenant_context do |message|
    repository_id = message[:repository_id]
    next if repository_id.nil? || repository_id.zero?
    ::Repositories::Public.resolve_tenant(id: repository_id)
  end

  METRIC_PREFIX = "hydro_swe_agent_close_reference_job"

  sig { void }
  def perform
    unless topic == "github.copilot.v0.AgentSessionStartPullRequest" || topic == "github.copilot.v0.AgentSessionPullRequestCreated"
      skip!("unsupported_topic")
      return
    end

    pull_request_id, initiating_user_id, agent_id, event_type, event_identifiers = message.values_at(:pull_request_id, :initiating_user_id, :agent_id, :event_type, :event_identifiers)
    unless event_type == "issues_agent_assignment"
      skip!("wrong_event_type")
      return
    end

    issue_id = extract_issue_id(event_identifiers)
    unless issue_id
      skip!("missing_issue_id")
      return
    end

    initiating_user = User.find_by(id: initiating_user_id)
    unless initiating_user
      skip!("missing_user")
      return
    end

    # The PR created by the agent
    pr_issue = Issue.includes(:pull_request).find_by(pull_request_id: pull_request_id)
    unless pr_issue
      skip!("missing_pull_request")
      return
    end

    # The issue that the agent was originally assigned to
    target_issue = Issues.domain.by_any(id: issue_id)
    unless target_issue
      skip!("missing_target_issue")
      return
    end

    # Check the initiating user, or the owner of the pr or target issue
    unless FeatureFlag.vexi.enabled?(:copilot_swe_agent_close_reference, [initiating_user, pr_issue.repository&.owner, Repository.find_by(id: target_issue.repository_id)&.owner], default: false)
      skip!("disabled")
      return
    end

    agent_bot = Integration.find_by(id: agent_id)&.bot
    unless agent_bot
      skip!("missing_agent")
      return
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      CloseIssueReference.create(
        issue: target_issue,
        pull_request: pr_issue.pull_request,
        source: :manual,
        actor_id: agent_bot.id,
      )
    rescue ActiveRecord::RecordNotUnique
      # Already linked — ignore duplicate
    end

    GitHub.dogstats.increment("#{METRIC_PREFIX}.created.count", tags: telemetry_tags)
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

  sig { params(event_identifiers: T.untyped).returns(T.nilable(Integer)) }
  def extract_issue_id(event_identifiers)
    return nil unless event_identifiers.is_a?(Array)

    event_identifiers.each do |identifier|
      next unless identifier.is_a?(String)

      match = identifier.match(/\Aissue_id::(\d+)\z/)
      return match[1].to_i if match
    end

    nil
  end
end
