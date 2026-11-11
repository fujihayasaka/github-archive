# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-users"

module Api::Internal::Twirp::Pullsd
  module Users
    module V1
      # Handler for the MonolithTwirp::Pullsd::Users::V1::UserAPIService
      class UserAPIHandler < Api::Internal::Twirp::Handler
        HELPERS = Class.new { include Api::Serializer::AvatarsDependency }.new

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
                login: user.login_for_api(use: :display), # TODO: We need to leverage serialize_login_selection and the `HTTP_X_SERIALIZE_LOGIN` header potentially.
                base_path: ::Api::LegacyEncode.encode("/users/#{user.login_for_api(use: :display)}", /\[|\]/),
                node_id: Platform::Helpers::GlobalId.for(user, user_preference: false, user_opt_out: false),
                avatar_url: HELPERS.avatar(user),
                profile_path: user.permalink(include_host: false),
                type: user.user_type,
                user_view_type: "public",
                site_admin: Api::Serializer.instance_admin?(user, viewer: nil),
                last_modified: T.unsafe(user).last_modified_at.to_proto,
                is_spammy: user.spammy?
              })
            end
          )
        end
      end
    end
  end
end
