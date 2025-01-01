# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-users"

module Api::Internal::Twirp::Pullsd
  module Users
    module V1
      # Handler for the MonolithTwirp::Pullsd::Users::V1::UserAPIService
      class UserAPIHandler < Api::Internal::Twirp::Handler
        HELPERS = Class.new { include Api::Serializer::AvatarsDependency }.new

        # TODO: Extract into a shared module to use in the API and in this endpoint
        EMPLOYEE_IDS_REFRESH = 1.hour

        # TODO: Extract into a shared module to use in the API and in this endpoint
        EMPLOYEE_IDS_KEY = "pullsd_github_employee_ids"

        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::Users::V1::UserAPIService

        # Public: Implementation of the ManyById Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Users::V1::ManyByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Users::V1::ManyByIdResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Users::V1::ManyByIdRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Pullsd::Users::V1::ManyByIdResponse, Twirp::Error))
        end
        def many_by_id(req, env)
          users = ::User.where(id: req.user_ids.to_a).to_a

          MonolithTwirp::Pullsd::Users::V1::ManyByIdResponse.new(
            users: users.map do |user|
              MonolithTwirp::Pullsd::Users::V1::User.new({
                id: user.id,
                login: user.login,
                base_path: ::Api::LegacyEncode.encode("/users/#{user.login_for_api}", /\[|\]/),
                node_id: Platform::Helpers::GlobalId.for(user, user_preference: false, user_opt_out: false),
                avatar_url: HELPERS.avatar(user),
                profile_path: user.permalink(include_host: false),
                type: user.user_type,
                user_view_type: "public",
                site_admin: instance_admin?(user, viewer: nil)
              })
            end
          )
        end

        # TODO: Extract into a shared module to use in the API and in this endpoint
        def instance_admin?(user, viewer:)
          return false unless user.user?
          return false if user.private_profile_for?(viewer)

          user.site_admin_without_two_factor_check? || github_employee?(user)
        end

        # TODO: Extract into a shared module to use in the API and in this endpoint
        def github_employee?(user)
          return false unless GitHub.require_employee_for_site_admin?

          github_employee_user_ids_set.include?(user.id)
        end

        # TODO: Extract into a shared module to use in the API and in this endpoint
        def github_employee_user_ids_set
          return @github_employee_user_ids_set if defined?(@github_employee_user_ids_set)

          return Set.new unless GitHub.require_employee_for_site_admin?

          github_employee_user_ids = GitHub.cache.fetch(EMPLOYEE_IDS_KEY, ttl: EMPLOYEE_IDS_REFRESH) do
            if team = FeatureFlag.employees_team
              team.member_ids
            else
              []
            end
          end

          @github_employee_user_ids_set = github_employee_user_ids.to_set
        end
      end
    end
  end
end
