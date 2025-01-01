# typed: true
# frozen_string_literal: true

require "github-proto-support"

class Api::Internal::Twirp < ::Api::Internal
  module Support
    module V1
      # Provides access to Support-relevant data.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Support::V1::UsersAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        GET_BILLING_INFO_HARD_LIMIT = 100

        # Public: Implementation of the GetBillingInfo Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Support::V1::GetBillingInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of billing info result for the users
        # a GitHub::Proto::Support::V1::GetBillingInfoResponse.
        def get_billing_info(req, env)
          scope_or_error = get_users_by_id(req.user_ids, argument_name: "user_ids",
            limit: GET_BILLING_INFO_HARD_LIMIT)
          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              results: build_billing_info_list(scope_or_error),
            }
          end
        end

        # Public: Implementation of the GetOrganizations Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetOrganizationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::GetOrganizationsResponse.
        def get_organizations(req, env)
          user_id = id_argument(req.user_id, env[:user_id])
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          all_organizations = (user.organizations +
                              user.billing_manager_organizations).uniq

          {
            results: build_organizations_info_list(all_organizations, user)
          }
        end

        private

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

        # Private: Convert an array of Organization objects to Twirp UserOrganizationsInfoResultItem
        #
        # organizations - The array of Organization objects.
        #
        # Returns an array of Hash objects that matches the Twirp UserOrganizationsInfoResultItem definition.
        def build_organizations_info_list(all_organizations, user)
          GitHub::PrefillAssociations.prefill_batch_method(all_organizations, :coupon_redemption)
          all_organizations.map do |org|
            {
              id: org.id,
              name: org.name,
              plan: org.plan.name,
              seats: org.seats,
              filled_seats: 1,
              is_verified: org.is_verified?,
              roles: org.role_of(user).types.map(&:to_s),
              enterprise_id: org&.business&.id,
              profile_name: org.profile_name,
              coupon_code: org.coupon_redemption&.coupon&.code,
              verified_domains: VerifiableDomain.where(owner: org, verified: true).limit(100).map(&:domain)
            }
          end
        end

        # Private: Convert an array of User objects to Twirp UserBillingInfoResultItem
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user id and billing info that matches the
        # Twirp UserBillingInfoResultItem definition.
        def build_billing_info_list(users)
          GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)
          users.map do |user|
            coupon_redemption = user.coupon_redemption
            {
              user_id: user.id,
              coupon_code: coupon_redemption&.coupon&.code,
              coupon_expires_at: coupon_redemption&.expires_at&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ"),
              is_paying_off_plan: user.help_hub_eligibility.eligible_based_on_usage_products?,
            }
          end
        end
      end
    end
  end
end
