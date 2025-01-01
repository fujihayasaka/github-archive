# typed: true
# frozen_string_literal: true

require "github-proto-users"

class Api::Internal::Twirp < ::Api::Internal
  module Users
    module V1
      # Provides access to User data.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Users::V1::UsersAPIService)
        allow_access_for :user, :client, allowed_clients: %w(helphub launch).freeze

        temporarily_exempt_from_tenant_context_requirement(until_date: "2024-04-01")

        GET_VISIBLE_USERS_HARD_LIMIT = 100

        GET_BLOCKING_USERS_HARD_LIMIT = 100

        FIND_USERS_HARD_LIMIT = 100

        ARE_EMAIL_VERIFIED_USERS_HARD_LIMIT = 100

        SEARCH_USERS_DEFAULT_LIMIT = 30
        SEARCH_USERS_HARD_LIMIT = 100

        # Public: Implementation of the FindUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::FindUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of users, suitable for use in
        # a GitHub::Proto::Users::V1::FindUsersResponse.
        def find_users(req, env)
          scope_or_error = get_users_by_id(req.ids, argument_name: "ids",
            limit: FIND_USERS_HARD_LIMIT)
          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              users: build_user_list(scope_or_error),
            }
          end
        end

        # Public: Implementation of the SearchUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::SearchUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::SearchUsersResponse.
        def search_users(req, env)
          if req.query.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "query")
          elsif req.limit > SEARCH_USERS_HARD_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{SEARCH_USERS_HARD_LIMIT}", argument: "query")
          else
            limit = req.limit == 0 ? SEARCH_USERS_DEFAULT_LIMIT : req.limit
            results = User.search(req.query, limit: limit)
          end
          {
            users: build_user_list(results),
          }
        end

        # Public: Implementation of the GetBlockingUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetBlockingUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::GetBlockingUsersResponse.
        def get_blocking_users(req, env)
          target_user_id = id_argument(req.target_user_id)
          unless target_user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "target_user_id")
          end

          scope_or_error = get_users_by_id(req.user_ids, argument_name: "user_ids",
            limit: GET_BLOCKING_USERS_HARD_LIMIT)
          return scope_or_error if scope_or_error.is_a?(Twirp::Error)

          results = build_user_blocking_result_items(scope_or_error,
            user_ids: req.user_ids.to_a,
            target_user_id: target_user_id)

          { results: results }
        end

        # Public: Implementation of the GetVisibleUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetVisibleUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::GetVisibleUsersResponse.
        def get_visible_users(req, env)
          scope_or_error = get_users_by_id(req.user_ids, argument_name: "user_ids",
            limit: GET_VISIBLE_USERS_HARD_LIMIT)
          return scope_or_error if scope_or_error.is_a?(Twirp::Error)

          results = build_user_visibility_result_items(scope_or_error,
            user_ids: req.user_ids.to_a,
            to_user_id: id_argument(req.to_user_id, env[:user_id]),
          )

          { results: results }
        end

        # Public: Implementation of the IsVisibleUser Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::IsVisibleUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::IsVisibleUserResponse.
        def is_visible_user(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          to_user_id = id_argument(req.to_user_id, env[:user_id])

          user = User.find(req.user_id)
          get_user_visibility_status(user, to_user_id: to_user_id)

        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # Public: Implementation of the AreEmailVerifiedUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::AreEmailVerifiedUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::AreEmailVerifiedUsersResponse.
        def are_email_verified_users(req, env)
          if req.user_ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_ids")
          end

          if req.user_ids.size > ARE_EMAIL_VERIFIED_USERS_HARD_LIMIT
            return Twirp::Error.invalid_argument(
              "must have a length <= #{ARE_EMAIL_VERIFIED_USERS_HARD_LIMIT}",
              argument: "user_ids",
            )
          end

          user_ids = req.user_ids.to_a # Google::Protobuf::RepeatedField
          verified_email_counts_by_user_id = UserEmail.verified.
            where(user_id: user_ids).group(:user_id).count
          results = user_ids.map do |user_id|
            build_user_email_verification_result(user_id,
              is_email_verified: (verified_email_counts_by_user_id[user_id] || 0) > 0)
          end

          {
            is_email_verification_enabled: GitHub.email_verification_enabled?,
            results: results,
          }
        end

        # Public: Implementation of the IsEmailVerifiedUser Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::IsEmailVerifiedUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::IsEmailVerifiedUserResponse.
        def is_email_verified_user(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find(user_id)

          if GitHub.email_verification_enabled?
            {
              is_email_verified: user.emails.verified.any?,
              is_email_verification_enabled: true,
            }
          else
            {
              is_email_verified: false,
              is_email_verification_enabled: false,
            }
          end
        end

        private

        def build_user_blocking_result_items(user_scope, user_ids:, target_user_id:)
          users = get_users_sorted_by_index_in_array(user_scope, user_ids: user_ids)
          user_ids_blocking_target_user = IgnoredUser.blocking(target_user_id).
            blocked_by(user_ids).index_by(&:user_id)
          users.map do |user|
            {
              user_id: user.id,
              is_blocking: user_ids_blocking_target_user.key?(user.id),
            }
          end
        end

        def build_user_visibility_result_items(user_scope, user_ids:, to_user_id:)
          users = get_users_sorted_by_index_in_array(user_scope, user_ids: user_ids)
          users.map do |user|
            result = get_user_visibility_status(user, to_user_id: to_user_id)
            result[:user_id] = user.id
            result
          end
        end

        # Private: Returns the given list of users sorted by where each user ID appears in the
        # given list.
        #
        # users - Array of User records
        # user_ids - Array of User IDs in the order you want the users sorted
        #
        # Returns an Array of User records.
        def get_users_sorted_by_index_in_array(users, user_ids:)
          indices_by_user_id = {}
          user_ids.each_with_index do |user_id, index|
            indices_by_user_id[user_id] = index
          end
          users.sort_by { |user| indices_by_user_id[user.id] }
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

        # Private: Checks if the given user is visible to the `to_user_id` user.
        #
        # user - the User whose visibility should be checked
        # to_user_id - ID of the viewer, if any; if omitted, visibility to anonymous viewers will
        #              be checked
        #
        # Returns a Hash suitable for use as a GitHub::Proto::Users::V1::IsVisibleUserResponse.
        def get_user_visibility_status(user, to_user_id:)
          if user.suspended?
            { is_visible: false, reason: :REASON_SUSPENDED }
          elsif GitHub.spamminess_check_enabled? && user.spammy?
            { is_visible: false, reason: :REASON_SPAMMY }
          elsif to_user_id && user.blocked_by?(to_user_id)
            { is_visible: false, reason: :REASON_BLOCKED }
          else
            { is_visible: true }
          end
        end

        # Private: Returns a hash for constructing a
        # GitHub::Proto::Users::V1::UserEmailVerificationResultItem.
        #
        # user_id - integer database ID for a User
        # is_email_verified - Boolean indicating if the user has a verified email address
        def build_user_email_verification_result(user_id, is_email_verified:)
          { user_id: user_id, is_email_verified: is_email_verified }
        end

        # Private: Returns a hash for constructing a
        # GitHub::Proto::Users::V1::UserVerifiedEmailsResultItem.
        #
        # user - User record
        def build_user_verified_emails_result(user)
          # mannequin's do not have verified emails
          return nil if user.mannequin?
          user.emails.verified.map do |email|
            {
              email: email.email,
              is_primary: email.primary?,
              visibility: get_email_visibility(email)
            }
          end
        end

        # Private: Gets the visibility of a UserEmail record.
        #
        # Returns an enum.
        def get_email_visibility(user_email)
          if user_email.public?
            :EMAIL_VISIBILITY_PUBLIC
          elsif user_email.private?
            :EMAIL_VISIBILITY_PRIVATE
          else
            :EMAIL_VISIBILITY_INVALID
          end
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
              avatar_url: user.primary_avatar_url,
              profile_url: "#{GitHub.url}/#{user.path}",
              email: user.email,
              is_site_admin: user.site_admin?,
              type: V1.user_type_enum(user),
              has_two_factor_authentication_enabled: user.two_factor_authentication_enabled?,
              plan_name: user.plan.name,
              verified_emails: build_user_verified_emails_result(user)
            }
          end
        end
      end
    end
  end
end
