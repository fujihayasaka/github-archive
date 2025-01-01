# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module Types
    class Actor < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :avatar_url, String
      const :type, String

      sig { params(actor: T.any(User, BusinessTeam, Team)).returns(Actor) }
      def self.from_model(actor)
        case actor
        when User
          Actor.new(
            id: actor.id,
            name: actor.safe_profile_name,
            description: actor.display_login,
            avatar_url: actor.primary_avatar_url,
            type: T.must(actor.class.name)
          )
        when BusinessTeam
          Actor.new(
            id: actor.id,
            name: actor.name,
            description: actor.description,
            # BusinessTeam avatars have not been fully implemented yet. It falls back to Team's impl, which fails in MT mode
            # Using the business avatar as a placeholder for now.
            # https://github.com/github/authz-exp/issues/304
            avatar_url: GitHub.multi_tenant_enterprise? ? T.must(actor.business).primary_avatar_url : actor.primary_avatar_url,
            type: T.must(actor.class.name)
          )
        when Team
          Actor.new(
            id: actor.id,
            name: actor.name,
            description: actor.description,
            avatar_url: actor.primary_avatar_url,
            type: T.must(actor.class.name)
          )
        else
          T.absurd(actor)
        end
      end
    end
  end
end
