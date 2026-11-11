# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for Mission Control agent experiment lifecycle events.
#
# 6 event types covering: assignment -> exposure -> preflight -> PR outcomes -> consent
#
# See: lib/hydro/schemas/github/mission_control_agent_experiment/v0/event.proto
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_ASSIGNMENT) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::ActorType,
        value: payload[:actor_type],
        default: :ACTOR_TYPE_UNKNOWN
      ),
      actor_id: payload[:actor_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      variant_name: payload[:variant_name],
      has_copilot: payload[:has_copilot],
      assigned_at: payload[:assigned_at],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.ExperimentAssignment")
  end

  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_EXPOSURE) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::ActorType,
        value: payload[:actor_type],
        default: :ACTOR_TYPE_UNKNOWN
      ),
      actor_id: payload[:actor_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      variant_name: payload[:variant_name],
      agent_surface_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::AgentSurfaceType,
        value: payload[:agent_surface_type],
        default: :AGENT_SURFACE_TYPE_UNKNOWN
      ),
      surface_entry_point: payload[:surface_entry_point],
      exposed_at: payload[:exposed_at],
      session_id: payload[:session_id],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.ExperimentExposure")
  end

  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_PREFLIGHT_RESULT) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor_id: payload[:actor_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      agent_surface_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::AgentSurfaceType,
        value: payload[:agent_surface_type],
        default: :AGENT_SURFACE_TYPE_UNKNOWN
      ),
      decision: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::PreflightResult::PreflightDecision,
        value: payload[:decision],
        default: :DECISION_UNKNOWN
      ),
      reason: payload[:reason],
      thresholds_checked: payload[:thresholds_checked],
      repository_id: payload[:repository_id],
      owner_id: payload[:owner_id],
      checked_at: payload[:checked_at],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.PreflightResult")
  end

  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_PR_CREATED) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      initiating_user_id: payload[:initiating_user_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      variant_name: payload[:variant_name],
      agent_surface_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::AgentSurfaceType,
        value: payload[:agent_surface_type],
        default: :AGENT_SURFACE_TYPE_UNKNOWN
      ),
      pull_request_id: payload[:pull_request_id],
      repository_id: payload[:repository_id],
      session_id: payload[:session_id],
      created_at: payload[:created_at],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.PrCreated")
  end

  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_PR_REVERTED) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      acting_user_id: payload[:acting_user_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      variant_name: payload[:variant_name],
      agent_surface_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::AgentSurfaceType,
        value: payload[:agent_surface_type],
        default: :AGENT_SURFACE_TYPE_UNKNOWN
      ),
      pull_request_id: payload[:pull_request_id],
      repository_id: payload[:repository_id],
      action: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::PrReverted::PrRevertAction,
        value: payload[:action],
        default: :REVERT_ACTION_UNKNOWN
      ),
      session_id: payload[:session_id],
      reverted_at: payload[:reverted_at],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.PrReverted")
  end

  subscribe(AzureEXP::Experiments::MissionControlPilot::EVENT_CONSENT_GIVEN) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor_id: payload[:actor_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      consent_type: payload[:consent_type],
      agent_surface_type: serializer.enum(
        type: Hydro::Schemas::Github::MissionControlAgentExperiment::V0::AgentSurfaceType,
        value: payload[:agent_surface_type],
        default: :AGENT_SURFACE_TYPE_UNKNOWN
      ),
      consented_at: payload[:consented_at],
    }

    publish(message, schema: "hydro.schemas.github.mission_control_agent_experiment.v0.ConsentGiven")
  end
end
