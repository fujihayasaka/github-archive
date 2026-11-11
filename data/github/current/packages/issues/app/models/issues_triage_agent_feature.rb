# typed: strict
# frozen_string_literal: true

# Represents the feature of issues triage agent.
# Provides helpers to check if a repository is enrolled in the triage agent.
module IssuesTriageAgentFeature
  extend T::Helpers

  # Feature flag for repository enrollment in triage agent
  REPO_ENROLLED_FLAG = :issues_triage_agent
  # Feature flag for local development fake triage mode
  LOCAL_DEV_FLAG = :issues_triage_agent_local_dev
  # Feature flag for the new config behavior, including config file requirement
  # and related allowlist/eligibility enforcement in the triage API.
  NEW_CONFIG = :issues_triage_agent_new_config
  # Feature flag for routing triage jobs through mission-control instead of direct sweagentd
  MISSION_CONTROL = :issues_triage_use_mission_control_tasks
  # Feature flag for creating AgentAssignment records when triage jobs are triggered
  AGENT_ASSIGNMENT = :issue_triage_agent_assignment

  # Check if a repository is enrolled for the triage agent.
  # Returns false for public repositories until Public Preview.
  # Checks the repository-scoped feature flag and that the Copilot Coding Agent is enabled.
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.enrolled?(repository)
    return false if repository.public?
    return false unless FeatureFlag.vexi.enabled?(REPO_ENROLLED_FLAG, repository, default: false)

    unless repository.owner&.copilot_swe_agent_enabled_for?(repository)
      GitHub.dogstats.increment("triage_agent.cca_not_enabled", tags: ["repo_enrolled_flag:true"])
      GitHub.logger.info("triage_agent.cca_not_enabled", {
        "code.namespace" => "IssuesTriageAgentFeature",
        "repository_id" => repository.id,
        "repository_nwo" => repository.name_with_display_owner,
      })
      return false
    end

    true
  end

  # Check if fake triage mode is enabled for local development.
  # Returns true only in development environment with the local dev feature flag globally enabled.
  sig { returns(T::Boolean) }
  def self.fake_triage_enabled?
    !!(Rails.env.development? && FeatureFlag.vexi.enabled?(LOCAL_DEV_FLAG, default: false))
  end

  # Check if the new config behavior is enabled for this repository.
  # When enabled, the triage agent will not run unless a config file is present,
  # and additional behaviors such as allowlist/eligibility enforcement may apply.
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.new_config_enabled?(repository)
    return false unless enrolled?(repository)

    repository.feature_flag_enabled?(NEW_CONFIG, default: false)
  end

  # Check if triage jobs should be routed through mission-control instead of direct sweagentd.
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.use_mission_control?(repository)
    return false unless enrolled?(repository)

    repository.feature_flag_enabled?(MISSION_CONTROL, default: false)
  end

  # Check if AgentAssignment records should be created for triage sessions.
  # Requires mission-control routing to be enabled (needs task_id from the response).
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.agent_assignment_enabled?(repository)
    return false unless use_mission_control?(repository)

    repository.feature_flag_enabled?(AGENT_ASSIGNMENT, default: false)
  end

  # Check if the repository is enrolled AND the viewer has Copilot Coding Agent access.
  # Use this for UI visibility gating (e.g., showing the triage agent button).
  # Unlike `enrolled?`, this includes a viewer-level license/SKU check.
  # Returns false when viewer is nil.
  sig { params(repository: Repository, viewer: T.nilable(User)).returns(T::Boolean) }
  def self.viewer_eligible?(repository, viewer)
    return false if viewer.nil?
    return false unless enrolled?(repository)

    repository.copilot_swe_agent_enabled?(viewer)
  end

end
