# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

module DependencySnapshot
  module EntitySerializer
    class User
      sig { params(user: ::User).returns(Github::DependencySnapshotsApi::Entities::User) }
      def self.serialize(user)
        type = case user.type
        when "Bot"
          :BOT
        when "Organization"
          :ORGANIZATION
        when "ProgrammaticAccessBot"
          :PROGRAMMATIC_ACCESS_BOT
        when "User"
          :USER
        end

        Github::DependencySnapshotsApi::Entities::User.new(
          id: user.id,
          # We _explicitly_ want the full, suffixed login here, so we can use it dependency-snapshots-api
          # We are also passing the display login so we can use it in user-facing UIs
          login: user.login, # rubocop:disable GitHub/DoNotAllowLogin
          display_login: user.display_login,
          type: type,
        )
      end
    end
  end
end
