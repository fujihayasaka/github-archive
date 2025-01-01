# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-users"

module Api::Internal::Twirp::Classroom
  module Users
    module V1
      # Handler for the MonolithTwirp::Classroom::Users::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::Users::V1::UsersAPIService

        # Public: Implementation of the GetUserOwnedOrganizations Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Users::V1::GetUserOwnedOrganizationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Users::V1::GetUserOwnedOrganizationsResponse, or a Twirp::Error.
        def get_user_owned_organizations(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user not found", argument: "user_id") unless user

          { results: build_user_owned_organizations(user) }
        end

        # Public: Implementation of the VerifyUserAdmin Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Users::V1::VerifyUserAdminRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Users::V1::VerifyUserAdminResponse, or a Twirp::Error.
        def verify_user_admin(req, env)
          unless id_argument(req.org_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "org_id")
          end

          unless id_argument(req.user_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          unless organization = Organization.find_by(id: req.org_id)
            return Twirp::Error.not_found("organization not found", argument: "org_id")
          end

          unless organization.people_ids.include?(req.user_id)
            return Twirp::Error.not_found("user not in organization", argument: "user_id")
          end

          unless user = User.find_by(id: req.user_id)
            return Twirp::Error.not_found("user not found", argument: "user_id")
          end

          organization.role_of(user).admin? ? { is_admin: true } : { is_admin: false }
        end

        private

        # Private: Returns a hash for constructing a
        # GitHub::Proto::Users::V1::GetUserOwnedOrganizations.
        #
        # user - User record
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_owned_organizations(user)
          user.owned_organizations.map do |org|
            {
              id: org.id,
              login: org.login,
              is_disabled: org.disabled,
              is_spammy: org.spammy
            }
          end
        end
      end
    end
  end
end
