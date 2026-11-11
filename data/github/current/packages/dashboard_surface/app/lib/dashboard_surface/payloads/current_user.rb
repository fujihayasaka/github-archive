# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    # Shared current user payload for all dashboard surfaces.
    # Serialized into the app-level payload for React hydration.
    #
    # This is part of the shared dashboard surface infrastructure.
    class CurrentUser < T::Struct
      const :id, Integer
      const :login, String
      const :avatarUrl, String
      const :is_staff, T::Boolean
      const :is_emu, T::Boolean
      const :name, T.nilable(String)

      sig { params(user: User).returns(CurrentUser) }
      def self.serialize(user)
        CurrentUser.new(
          id: user.id,
          login: user.display_login,
          avatarUrl: user.primary_avatar_url,
          is_staff: user.employee?,
          is_emu: user.is_enterprise_managed?,
          name: user.display_name,
        )
      end
    end
  end
end
