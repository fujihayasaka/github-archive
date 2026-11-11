# typed: true
# frozen_string_literal: true

# Shared concern for serializing AgenticApp agent information into a
# consistent JSON-ready hash.  Used by both CopilotSessions::AgentInfoController
# and Issues::AgentTasksController so every endpoint returns the same shape.
module AgentInfoSerialization
  extend ActiveSupport::Concern

  private

  # Builds a canonical hash of agent information suitable for JSON rendering.
  #
  # agent  - An object implementing the AgenticApp interface.
  # viewer - The User whose feature-flag context determines optional fields.
  #
  # Returns a Hash with Symbol keys.
  sig { params(agent: T.untyped, viewer: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
  def serialize_agent_info(agent, viewer:)
    info = {
      id: agent.integration.id,
      name: agent.display_name,
      slug: agent.slug,
      display_name: agent.display_name,
      avatar_url: agent.integration.preferred_avatar_url(size: 60),
      doc_url: agent.doc_url,
    }

    if FeatureFlag.vexi.enabled?(:include_agent_global_relay_id, viewer, default: false)
      info[:bot_global_relay_id] = agent.integration.bot.global_relay_id
    end

    info
  end
end
