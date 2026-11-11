# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  module AlertsSerializer
    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_assignee(user)
      if user.is_a?(Bot)
        agent = AgenticApp.agent_for_bot_id(user.id)
        is_copilot = agent.present? && user.integration.present? && Apps::Privileged.capable?(:is_copilot, app: user.integration)

        {
          id: user.id,
          login: user.slug,
          name: user.display_name,
          avatarUrl: user.primary_avatar_url(64),
          profilePath: user.integration&.public_app_path,
          isCopilot: is_copilot,
          isAgent: agent.present?,
          displayName: agent&.display_name,
        }
      else
        {
          id: user.id,
          login: user.display_login,
          name: user.display_name,
          avatarUrl: user.primary_avatar_url(64),
          profilePath: "/#{user.display_login}",
          isCopilot: false,
          isAgent: false,
          displayName: nil,
        }
      end
    end
  end
end
