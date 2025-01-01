# typed: true
# frozen_string_literal: true

require "monolith-twirp-content_engine-core"

module Api::Internal::Twirp::ContentEngine
  module Core
    module V1
      # Provides access to ContentEngine-relevant data.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::ContentEngine::Core::V1::UsersAPIService)

        allow_access_for :user, :client, allowed_clients: %w(content_engine).freeze

        FIND_USERS_HARD_LIMIT = 100

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ContentEngine::Core::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of users, suitable for use in
        # a MonolithTwirp::ContentEngine::Core::V1::GetUsersResponse.
        def get_users(req, env)
          scope_or_error = get_users_by_id(req.user_ids, argument_name: "user_ids",
            limit: FIND_USERS_HARD_LIMIT)
          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              users: build_user_list(scope_or_error),
            }
          end
        end

        private

        # Private: Get users by their IDs with a limit check.
        #
        # ids - Array of user IDs.
        # argument_name - Name of the argument for error messages.
        # limit - Maximum number of IDs allowed.
        #
        # Returns a User scope or a Twirp::Error if the limit is exceeded.
        def get_users_by_id(ids, argument_name:, limit:)
          if ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}", argument: argument_name)
          end

          User.where(id: ids.to_a)
        end

        # Private: Convert an array of User objects to the shape Twirp responses expect.
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_list(users)
          users.map do |user|
            build_user_result(user)
          end
        end

        # Private: Returns a hash for constructing a UserListItem.
        #
        # user - User record
        def build_user_result(user)
          {
            id: user.id,
            login: user.login,
            name: user.safe_profile_name
          }
        end
      end
    end
  end
end
