# typed: strict
# frozen_string_literal: true

require "azure_exp/experiments/mission_control_pilot"

# Concern for emitting Mission Control experiment Hydro events from controllers.
#
# Provides helper methods to emit experiment lifecycle events (exposure, etc.)
# gated behind the :mission_control_experiment_hydro_events feature flag.
#
# Include in any controller that serves as an agent interaction surface.
#
# The emitter methods accept an `experiment:` keyword so different experiment
# modules can reuse the same plumbing. Any module passed must expose:
#   - FEATURE_FLAG           (Symbol)   – the feature-flag gate for enrollment
#   - EXPERIMENT_PARAMETER   (String)   – the experiment name sent in payloads
#   - variant_for(user)      (method)   – returns { number: Integer, name: String }
#   - EVENT_EXPOSURE         (String)   – Hydro event name for exposure
#   - EVENT_CONSENT_GIVEN    (String)   – Hydro event name for consent
#   - EVENT_PREFLIGHT_RESULT (String)   – Hydro event name for preflight results
#   - EVENT_PR_CREATED       (String)   – Hydro event name for PR creation
#   - EVENT_PR_REVERTED      (String)   – Hydro event name for PR revert/close
#
# Defaults to AzureEXP::Experiments::MissionControlPilot when no experiment is
# specified, keeping existing call sites unchanged.
module MissionControlExperimentEvents
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  # How long to suppress duplicate exposure events for the same
  # user × surface × entry_point combination.
  EXPOSURE_DEDUP_TTL = T.let(1.day, ActiveSupport::Duration)

  # The default experiment module used when callers don't specify one.
  DEFAULT_EXPERIMENT = T.let(AzureEXP::Experiments::MissionControlPilot, T.untyped)

  # Constants every experiment module must define. Used by {resolve_experiment_constants}
  # to validate configuration at call time rather than raising NameError mid-request.
  REQUIRED_EXPERIMENT_CONSTANTS = T.let(
    [:FEATURE_FLAG, :EXPERIMENT_PARAMETER].freeze,
    T::Array[Symbol],
  )

  private

  # Validate that +experiment+ defines the required constants and the requested
  # +event_constant+, then return a hash with the resolved values.
  #
  # Returns +nil+ when the experiment module is missing a required constant so
  # callers can return early instead of raising a 500.  Logs a warning so
  # misconfiguration is easy to diagnose in production.
  sig do
    params(
      experiment: T.untyped,
      event_constant: Symbol,
    ).returns(
      T.nilable({ feature_flag: Symbol, experiment_name: String, event_name: String }),
    )
  end
  def resolve_experiment_constants(experiment, event_constant)
    missing = REQUIRED_EXPERIMENT_CONSTANTS.reject { |c| experiment.const_defined?(c, false) }
    missing << event_constant unless experiment.const_defined?(event_constant, false)

    if missing.any?
      Rails.logger.warn(
        "[MissionControlExperimentEvents] Experiment module #{experiment} is missing constants: #{missing.join(", ")}. Skipping event emission.",
      )
      return nil
    end

    {
      feature_flag: T.cast(experiment.const_get(:FEATURE_FLAG), Symbol),
      experiment_name: T.cast(experiment.const_get(:EXPERIMENT_PARAMETER), String),
      event_name: T.cast(experiment.const_get(event_constant), String),
    }
  end

  # Shared gate: returns the current user only when both the global hydro-events
  # flag and the per-experiment feature flag are enabled.
  sig { params(feature_flag: Symbol).returns(T.nilable(User)) }
  def gated_experiment_user(feature_flag)
    user = current_user
    return unless user
    return unless user.feature_flag_enabled?(:mission_control_experiment_hydro_events, default: false)
    return unless user.feature_flag_enabled?(feature_flag, default: false)

    user
  end

  # Emit an EXPOSURE event when the user sees an agent surface.
  # Deduplicates per user × surface × entry_point × experiment across requests
  # using the application cache with a 1-day TTL so repeated page loads don't
  # flood Hydro.
  #
  # @param surface_type [Symbol] e.g. :AGENT_SURFACE_TYPE_MISSION_CONTROL
  # @param entry_point [String] e.g. "repo_agents_index", "agent_task_view"
  # @param session_id [String, nil] optional Copilot session ID
  # @param experiment [Module] experiment module providing constants & variant_for
  sig do
    params(
      surface_type: Symbol,
      entry_point: String,
      session_id: T.nilable(String),
      experiment: T.untyped,
    ).void
  end
  def emit_experiment_exposure(surface_type:, entry_point:, session_id: nil, experiment: DEFAULT_EXPERIMENT)
    config = resolve_experiment_constants(experiment, :EVENT_EXPOSURE)
    return unless config

    user = gated_experiment_user(config[:feature_flag])
    return unless user

    cache_key = "mc_exp_exposure:#{user.id}:#{surface_type}:#{entry_point}:#{config[:experiment_name]}"
    return if GitHub.cache.exist?(cache_key)

    GitHub.cache.write(cache_key, true, expires_in: EXPOSURE_DEDUP_TTL)

    v = experiment.variant_for(user)

    GlobalInstrumenter.instrument(config[:event_name], {
      actor_type: :ACTOR_TYPE_USER,
      actor_id: user.id,
      actor_analytics_tracking_id: user.analytics_tracking_id,
      experiment_name: config[:experiment_name],
      variant: v[:number],
      variant_name: v[:name],
      agent_surface_type: surface_type,
      surface_entry_point: entry_point,
      exposed_at: Time.current,
      session_id: session_id,
    })
  end

  # Emit a CONSENT_GIVEN event when a user explicitly opts in (or out) of
  # agent checks / actions.
  #
  # @param surface_type [Symbol] the agent surface where consent was given
  # @param consent_type [String] e.g. "run_checks", "skip_checks"
  # @param experiment [Module] experiment module providing constants & variant_for
  sig do
    params(
      surface_type: Symbol,
      consent_type: String,
      experiment: T.untyped,
    ).void
  end
  def emit_experiment_consent_given(surface_type:, consent_type:, experiment: DEFAULT_EXPERIMENT)
    config = resolve_experiment_constants(experiment, :EVENT_CONSENT_GIVEN)
    return unless config

    user = gated_experiment_user(config[:feature_flag])
    return unless user

    v = experiment.variant_for(user)

    GlobalInstrumenter.instrument(config[:event_name], {
      actor_id: user.id,
      actor_analytics_tracking_id: user.analytics_tracking_id,
      experiment_name: config[:experiment_name],
      variant: v[:number],
      consent_type: consent_type,
      agent_surface_type: surface_type,
      consented_at: Time.current,
    })
  end

  # Emit a PREFLIGHT_RESULT event after running preflight checks (lint, tests,
  # security scans) before PR creation.
  #
  # @param surface_type [Symbol] the agent surface that triggered the preflight
  # @param decision [Symbol] :DECISION_ALLOWED or :DECISION_BLOCKED
  # @param reason [String, nil] human-readable explanation when blocked
  # @param thresholds_checked [String, nil] JSON-encoded list of threshold names evaluated
  # @param repository_id [Integer, nil] scoped repository
  # @param owner_id [Integer, nil] repository owner
  # @param experiment [Module] experiment module providing constants & variant_for
  sig do
    params(
      surface_type: Symbol,
      decision: Symbol,
      reason: T.nilable(String),
      thresholds_checked: T.nilable(String),
      repository_id: T.nilable(Integer),
      owner_id: T.nilable(Integer),
      experiment: T.untyped,
    ).void
  end
  def emit_experiment_preflight_result(surface_type:, decision:, reason: nil, thresholds_checked: nil, repository_id: nil, owner_id: nil, experiment: DEFAULT_EXPERIMENT)
    config = resolve_experiment_constants(experiment, :EVENT_PREFLIGHT_RESULT)
    return unless config

    user = gated_experiment_user(config[:feature_flag])
    return unless user

    v = experiment.variant_for(user)

    GlobalInstrumenter.instrument(config[:event_name], {
      actor_id: user.id,
      actor_analytics_tracking_id: user.analytics_tracking_id,
      experiment_name: config[:experiment_name],
      variant: v[:number],
      agent_surface_type: surface_type,
      decision: decision,
      reason: reason,
      thresholds_checked: thresholds_checked,
      repository_id: repository_id,
      owner_id: owner_id,
      checked_at: Time.current,
    })
  end

  # Emit a PR_CREATED event when an agent opens a draft pull request as part of
  # an experiment.
  #
  # @param surface_type [Symbol] the agent surface that created the PR
  # @param pull_request_id [Integer] the new PR's database ID
  # @param repository_id [Integer] the target repository
  # @param session_id [String, nil] optional Copilot session ID
  # @param experiment [Module] experiment module providing constants & variant_for
  sig do
    params(
      surface_type: Symbol,
      pull_request_id: Integer,
      repository_id: Integer,
      session_id: T.nilable(String),
      experiment: T.untyped,
    ).void
  end
  def emit_experiment_pr_created(surface_type:, pull_request_id:, repository_id:, session_id: nil, experiment: DEFAULT_EXPERIMENT)
    config = resolve_experiment_constants(experiment, :EVENT_PR_CREATED)
    return unless config

    user = gated_experiment_user(config[:feature_flag])
    return unless user

    v = experiment.variant_for(user)

    GlobalInstrumenter.instrument(config[:event_name], {
      initiating_user_id: user.id,
      actor_analytics_tracking_id: user.analytics_tracking_id,
      experiment_name: config[:experiment_name],
      variant: v[:number],
      variant_name: v[:name],
      agent_surface_type: surface_type,
      pull_request_id: pull_request_id,
      repository_id: repository_id,
      session_id: session_id,
      created_at: Time.current,
    })
  end

  # Emit a PR_REVERTED event when a user closes or reverts an agent-created PR.
  #
  # @param surface_type [Symbol] the agent surface associated with the PR
  # @param pull_request_id [Integer] the PR being reverted/closed
  # @param repository_id [Integer] the target repository
  # @param action [Symbol] :REVERT_ACTION_CLOSED or :REVERT_ACTION_REVERTED
  # @param session_id [String, nil] optional Copilot session ID
  # @param experiment [Module] experiment module providing constants & variant_for
  sig do
    params(
      surface_type: Symbol,
      pull_request_id: Integer,
      repository_id: Integer,
      action: Symbol,
      session_id: T.nilable(String),
      experiment: T.untyped,
    ).void
  end
  def emit_experiment_pr_reverted(surface_type:, pull_request_id:, repository_id:, action:, session_id: nil, experiment: DEFAULT_EXPERIMENT)
    config = resolve_experiment_constants(experiment, :EVENT_PR_REVERTED)
    return unless config

    user = gated_experiment_user(config[:feature_flag])
    return unless user

    v = experiment.variant_for(user)

    GlobalInstrumenter.instrument(config[:event_name], {
      acting_user_id: user.id,
      actor_analytics_tracking_id: user.analytics_tracking_id,
      experiment_name: config[:experiment_name],
      variant: v[:number],
      variant_name: v[:name],
      agent_surface_type: surface_type,
      pull_request_id: pull_request_id,
      repository_id: repository_id,
      action: action,
      session_id: session_id,
      reverted_at: Time.current,
    })
  end
end
