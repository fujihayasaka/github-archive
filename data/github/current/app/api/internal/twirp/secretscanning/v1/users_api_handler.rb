# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      # Provides access to User data.
      class UsersAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Users::V1::UsersAPIService)

        allow_access_for :client

        FIND_USERS_HARD_LIMIT = 100

        exempt_from_tenant_context_requirement

        # Public: Implementation of the FindUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::SecretScanning::Users::V1::FindUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of users, suitable for use in
        # a GitHub::Proto::SecretScanning::Users::V1::FindUsersResponse.
        def find_users(req, env)
          if req.business_selector.present?
            return get_users_by_business(req.business_selector.id, req.cursor)
          elsif req.ids.present?
            scope_or_error = get_users_by_id(req.ids, argument_name: "ids",
              limit: FIND_USERS_HARD_LIMIT)
          elsif req.ids_selector.present?
            scope_or_error = get_users_by_id(req.ids_selector.ids, argument_name: "selector.ids",
              limit: FIND_USERS_HARD_LIMIT)
          elsif req.logins_selector.present?
            scope_or_error = get_users_by_login(req.logins_selector.logins, argument_name: "selector.logins",
              limit: FIND_USERS_HARD_LIMIT)
          else
            return Twirp::Error.invalid_argument("invalid selector",
              argument: "selector")
          end

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              users: build_user_list(scope_or_error),
            }
          end
        end

        private

        def get_users_by_business(business_id, cursor)
          next_cursor = nil
          last_processed_page = cursor.present? ? cursor.unpack("Q")[0] : 1

          biz = Business.find_by(id: business_id)
          unless biz.present?
            return Twirp::Error.invalid_argument("failed to fetch business", argument: "business_selector.id")
          end

          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)
          unless feature.feature_available_for_user_repositories?
            GitHub.logger.info("Attempted to list users for unsupported business", {
              business_id: business_id,
            })
            return { users: [], next_cursor: nil, }
          end

          user_scope = feature.list_enterprise_users_paged(page: last_processed_page, per_page: FIND_USERS_HARD_LIMIT)

          # If we got FIND_USERS_HARD_LIMIT users, there might be more, so we need to set a new cursor.
          if user_scope.length == FIND_USERS_HARD_LIMIT
            next_cursor = [last_processed_page + 1].pack("Q")
          end

          {
            users: build_user_list(user_scope),
            next_cursor: next_cursor,
          }
        end

        # Private: Returns Users for each of the given user IDs.
        #
        # ids - User IDs in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of User, or a Twirp::Error.
        def get_users_by_id(ids, argument_name:, limit:)
          if ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # ids is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          User.where(id: ids.to_a)
        end

        # Private: Returns Users for each of the given user logins.
        #
        # logins - User logins in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of User, or a Twirp::Error.
        def get_users_by_login(logins, argument_name:, limit:)
          if logins.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if logins.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # login is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          User.where(login: logins.to_a)
        end

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
              login: user.login,
              name: user.safe_profile_name,
              email: user.email,
              type: user_type_enum(user),
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
          when Mannequin
            :USER_TYPE_MANNEQUIN
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
