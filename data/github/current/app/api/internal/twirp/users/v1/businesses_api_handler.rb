# typed: true
# frozen_string_literal: true

require "github-proto-users"

class Api::Internal::Twirp < ::Api::Internal
  module Users
    module V1
      # Provides access to business data.
      class BusinessesAPIHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Users::V1::BusinessesAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        GET_BUSINESSES_HARD_LIMIT = 100

        # Public: Implementation of the GetBusinesses Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::GetBusinessesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of businesses, suitable for use in a
        # GitHub::Proto::Users::V1::GetBusinessesResponse.
        def get_businesses(req, env)
          business_ids = req.business_ids
          user_id = id_argument(req.user_id)

          case
          when business_ids.present? && user_id.present?
            return Twirp::Error.invalid_argument("one must be non-empty", arguments: "business_ids, user_id")
          when business_ids.present?
            scope_or_error = businesses_for_business_ids(business_ids)
          when user_id.present?
            scope_or_error = businesses_for_user_id(user_id)
          else
            return Twirp::Error.invalid_argument("one must be non-empty", arguments: "business_ids, user_id")
          end

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            { businesses: build_business_list(scope_or_error) }
          end
        end

        private

        # Private: Convert an array of business ids into Business objects.
        #
        # business_ids - The array of business ids.
        #
        # Returns a scope of Business objects or a Twirp::Error
        def businesses_for_business_ids(business_ids, limit = GET_BUSINESSES_HARD_LIMIT)
          if business_ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}", argument: "business_ids")
          end

          Business.where(id: business_ids.to_a)
        end

        # Private: Convert an user id into Business objects.
        #
        # user_id - The user id.
        #
        # Returns a scope of Business objects or a Twirp::Error
        def businesses_for_user_id(user_id)
          user = User.find_by(id: user_id)
          if user.nil?
            return Twirp::Error.invalid_argument("does not exist", argument: "user_id")
          end

          (user.businesses(membership_type: :admin) +
            user.businesses(membership_type: :billing_manager) +
            user.businesses(membership_type: :support_entitled)).uniq
        end

        # Private: Convert an array of EnterpriseInstallation objects to the shape a Twirp response expects.
        #
        # enterprise_installations - The array of EnterpriseInstallation objects.
        #
        # Returns an array of Hash objects with installation data that matches the EnterpriseInstallationsListItem Twirp definition.
        def build_enterprise_installations(enterprise_installations)
          enterprise_installations.map do |installation|
            {
              id: installation.id,
              host_name: installation.host_name,
              created_at: Google::Protobuf::Timestamp.new(seconds: installation.created_at.to_i),
              license_hash: Digest::SHA256.base64digest(installation.license_hash),
              customer_name: installation.customer_name,
              version: installation.version
            }
          end
        end

        # Private: Convert an array of GitHub::EnterpriseWeb::License objects to the shape a Twirp response expects.
        #
        # business - A business object.
        #
        # Returns an array of Hash objects with business data that matches the EnterpriseInstallationsListItem Twirp definition.
        def build_enterprise_server_licenses(business)
          return [] unless business.enterprise_web_business_id.present?
          licenses = GitHub::EnterpriseWeb::License.all(business.enterprise_web_business_id).sort_by(&:expires_at)
          licenses.map do |license|
            {
              id: license.id,
              created_at: protobuf_timestamp_if_present(license.created_at),
              updated_at: protobuf_timestamp_if_present(license.updated_at),
              starts_at: protobuf_timestamp_if_present(license.starts_at),
              expires_at: Google::Protobuf::Timestamp.new(seconds: license.expires_at.to_time.to_i),
              seats: license.seats,
              learning_lab_seats: license.learning_lab_seats,
              learning_lab_evaluation_expires_at: protobuf_timestamp_if_present(license.learning_lab_evaluation_expires_at),
              checksum: license.checksum,
              type: license.type,
              state: license.state
            }
          end
        rescue Faraday::Error => e
          Failbot.report(e)
          []
        end

        # Private: Convert an array of Business objects to the shape Twirp responses expect.
        #
        # businesses - The array of Business objects.
        #
        # Returns an array of Hash objects with business data that matches the Twirp definition.
        def build_business_list(businesses)
          businesses.map do |business|
            {
              id: business.id,
              name: business.name,
              installations: build_enterprise_installations(business.enterprise_installations),
              slug: business.slug,
              licenses: build_enterprise_server_licenses(business),
              support_plan: business.calculated_support_plan
            }
          end
        end

        # If the given value is present, format it as a protobuf timestamp. Otherwise, return nil.
        # @param value [DateTime, nil]
        # @return [Google::Protobuf::Timestamp, nil]
        def protobuf_timestamp_if_present(value)
          value.present? ? Google::Protobuf::Timestamp.new(seconds: value.to_time.to_i) : nil
        end
      end
    end
  end
end
