# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  module AlertsSerializer
    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_assignee(user)
      {
        id: user.id,
        login: user.display_login,
        name: user.profile_name,
        avatarUrl: user.primary_avatar_url(64),
        profilePath: "/#{user.display_login}",
        isCopilot: false, # Bots not supported yet; make dynamic when Copilot support is added
      }
    end
  end
end
