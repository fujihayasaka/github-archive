# typed: true
# frozen_string_literal: true

# Shared concern for serializing AgenticApp agent information into a
# consistent JSON-ready hash.  Used by both CopilotSessions::AgentInfoController
# and Issues::AgentTasksController so every endpoint returns the same shape.
module AgentInfoSerialization
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  private

  # Builds a canonical hash of agent information suitable for JSON rendering.
  #
  # agent  - An object implementing the AgenticApp interface.
  #
  # Returns a Hash with Symbol keys.
  sig { params(agent: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def serialize_agent_info(agent)
    info = {
      id: agent.integration.id,
      name: agent.display_name,
      slug: agent.slug,
      display_name: agent.display_name,
      avatar_url: agent.integration.preferred_avatar_url(size: 60),
      doc_url: agent.doc_url,
      model_vendor: agent.model_vendor,
      bot_global_relay_id: agent.integration.bot.global_relay_id,
      assignable: agent.assignable?,
      group: agent.group,
    }

    if FeatureFlag.vexi.enabled?(:copilot_engine_sdk_model_selection, current_user, default: false)
      info[:model_vendors] = agent.model_vendors
    end

    info
  end
end
