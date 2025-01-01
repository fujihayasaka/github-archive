# typed: true
# frozen_string_literal: true

require "github-proto-users"

class Api::Internal::Twirp < ::Api::Internal
  module Users
    module V1
      # Provides access to User following data.
      class FollowingAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Users::V1::FollowingAPIService)

        allow_access_for :user, :client

        # Public: Implementation of the GetFollowingUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetFollowingUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, suitable for use in a
        # GitHub::Proto::Users::V1::GetFollowingUsersResponse.
        def get_following_users(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument(
              "must be non-empty if a user token is not provided", argument: "user_id"
            )
          end

          check_user_ids = Array(req.check_user_ids)
          if check_user_ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "check_user_ids")
          end

          following_user_ids = Following.followed_by(check_user_ids).follower_of(user_id).
            pluck(:user_id)

          { following_user_ids: following_user_ids }
        end

        # Public: Implementation of the IsFollowing Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::IsFollowingRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, suitable for use in a
        # GitHub::Proto::Users::V1::IsFollowingResponse.
        def is_following(req, env)
          followed_user_id = id_argument(req.followed_user_id)
          unless followed_user_id
            return Twirp::Error.invalid_argument("must be non-empty",
                                                 argument: "followed_user_id")
          end

          follower_user_id = id_argument(req.follower_user_id, env[:user_id])
          unless follower_user_id
            return Twirp::Error.invalid_argument("must be non-empty if a user token is not provided",
                                                 argument: "follower_user_id")
          end

          {
            is_following: Following.followed_by(follower_user_id).follower_of(followed_user_id).exists?,
          }
        end

        # Public: Implementation of the SelectMutualFollowers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::SelectMutualFollowersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, suitable for use in a
        # GitHub::Proto::Users::V1::SelectMutualFollowersResponse.
        def select_mutual_followers(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty if a user token is not provided",
              argument: "user_id")
          end

          check_user_ids = Array(req.check_user_ids)
          if check_user_ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "check_user_ids")
          end

          followed_user_ids = Following.followed_by(user_id).follower_of(check_user_ids).pluck(:following_id)
          follower_user_ids = Following.followed_by(check_user_ids).follower_of(user_id).pluck(:user_id)
          intersection = followed_user_ids & follower_user_ids

          {
            mutual_follower_user_ids: intersection,
          }
        end
      end
    end
  end
end
