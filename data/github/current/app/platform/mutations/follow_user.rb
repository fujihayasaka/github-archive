# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class FollowUser < Platform::Mutations::Base
      description "Follow a user."

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:follow, resource: inputs[:user],
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: true)
      end

      minimum_accepted_scopes ["user:follow"]

      argument :user_id, ID, "ID of the user to follow.", required: true, loads: Objects::User

      field :user, Objects::User, "The user that was followed.", null: true

      def resolve(user:)
        viewer = context[:viewer]
        if user.followed_by?(viewer) || viewer.follow(user, context: "api")
          { user: user }
        else
          raise Platform::Errors::Execution.new("User failed to follow.")
        end
      end
    end
  end
end
