# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependency_graph-users"

module Api::Internal::Twirp::DependencyGraph
  module Users
    module V1
      # Handler for the MonolithTwirp::DependencyGraph::Users::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["dependency_graph_api"]
        handles_service MonolithTwirp::DependencyGraph::Users::V1::UsersAPIService

        GET_USERS_HARD_LIMIT = 100

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::DependencyGraph::Users::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::DependencyGraph::Users::V1::GetUsersResponse, or a Twirp::Error.
        def get_users(req, env)
          if req.ids.size > GET_USERS_HARD_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{GET_USERS_HARD_LIMIT}",
              argument: "ids")
          end

          # ids is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          { users: build_user_list(User.where(id: req.ids.to_a).includes(:profile)) }
        end

        private

        # Private: Convert an array of User objects to the shape Twirp responses expect.
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_list(users)
          users.map do |user|
            {
              id: user.id,
              type: user_type_enum(user),
              profile_name: user.safe_profile_name
            }
          end
        end

        # Public: Generate the UserType enum for a user.
        #
        # user - A User
        #
        # Returns a Symbol.
        def user_type_enum(user)
          case user
          when Organization
            :USER_TYPE_ORGANIZATION
          when Bot
            :USER_TYPE_BOT
          when User
            :USER_TYPE_USER
          else
            :USER_TYPE_INVALID
          end
        end
      end
    end
  end
end
