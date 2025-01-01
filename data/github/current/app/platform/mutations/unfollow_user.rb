# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnfollowUser < Platform::Mutations::Base
      description "Unfollow a user."

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:unfollow, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: true)
      end

      minimum_accepted_scopes ["user:follow"]

      argument :user_id, ID, "ID of the user to unfollow.", required: true, loads: Objects::User

      field :user, Objects::User, "The user that was unfollowed.", null: true

      def resolve(user:)
        if !user.followed_by?(context[:viewer]) || context[:viewer].unfollow(user, context: "api")
          { user: user }
        else
          raise Errors::Unprocessable.new("User failed to unfollow.")
        end
      end
    end
  end
end
