# typed: true
# frozen_string_literal: true

require "github-proto-users"

class Api::Internal::Twirp < ::Api::Internal
  module Users
    module V1

      # Convert SignedAuthToken tokens to user identities.
      class TokensAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Users::V1::TokensAPIService)

        allow_access_for :user, :client, require_user_token: true

        # Public: Implementation of the IdentifyTokenUser Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::IdentifyTokenUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::IdentifyTokenUserResponse.
        def identify_token_user(req, env)
          if env[:user_id]
            user = User.find_by(id: env[:user_id])
            {
              user: token_user_identity(user),
            }
          else
            {}
          end
        end

        private

        def token_user_identity(user)
          return nil unless user
          {
            id: user.id,
            login: user.login,
            name: user.safe_profile_name,
            avatar_url: user.primary_avatar_url,
            type: V1.user_type_enum(user),
          }
        end
      end
    end
  end
end
