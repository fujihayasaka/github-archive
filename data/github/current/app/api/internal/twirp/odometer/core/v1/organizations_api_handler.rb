# typed: true
# frozen_string_literal: true

require "monolith-twirp-odometer-core"

module Api::Internal::Twirp::Odometer
  module Core
    module V1
      # Provides access to organization data.
      class OrganizationsAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Odometer::Core::ActionsUsage

        handles_service(MonolithTwirp::Odometer::Core::V1::OrganizationsAPIService)

        allow_access_for :user, :client, allowed_clients: %w(odometer).freeze

        # Public: Implementation of the GetOrganizations Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Odometer::Core::V1::GetOrganizationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of organizations, suitable for use in a
        # MonolithTwirp::Odometer::Core::V1::GetOrganizationsResponse.
        def get_organizations(req, env)
          organization_slugs = req.organization_slugs.to_a
          organization_ids = if organization_slugs.any?
            Business.where(login: organization_slugs).pluck(:id)
          else
            req.organization_ids.to_a
          end

          scope_or_error = organizations_for_organization_ids(organization_ids)

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          elsif scope_or_error.is_a?(Hash)
            { organizations: scope_or_error.flat_map { |organizations| build_organization_list(organizations) } }
          else
            { organizations: build_organization_list(scope_or_error) }
          end
        end

        private

        def organizations_for_organization_ids(organization_ids, limit = 100)
          if organization_ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}", argument: "organization_ids")
          end

          ::Organization.where(id: organization_ids)
        end

        def build_organization_list(organizations)
          organizations.map do |org|
            org = T.let(org, Organization)
            {
              id: org.id,
              slug: org.display_login,
              created_at: protobuf_timestamp_if_present(org.created_at),
              business_owned: org.business.present?,
              plan_name: org.plan_name,
              payment_method: payment_method(org),
              has_azure_id: org.customer&.azure_subscription_id.present?,
              user_count: org.filled_seats,
              purchased_volume_licenses: org.seats,
              repository_count: org.repositories.count,
              actions_consumed: actions_consumed(org),
              copilot_seats: ::Copilot::Seat.for_organization(org).count,
              advanced_security_secret_protection_seats_used: org.secret_protection.seats_used,
              advanced_security_code_security_seats_used: org.code_security.seats_used,
              advanced_security_maximum_committers: org.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).entity_summary.maximum_committers,
            }
          end
        end

        # If the given value is present, format it as a protobuf timestamp. Otherwise, return nil.
        # @param value [Date, DateTime, nil]
        # @return [Google::Protobuf::Timestamp, nil]
        def protobuf_timestamp_if_present(value)
          return nil unless value.respond_to?(:to_time)

          Google::Protobuf::Timestamp.new(seconds: value.to_time.to_i)
        end

        def payment_method(org)
          if org.customer&.invoiced?
            "invoice"
          elsif org.payment_method&.card_type.present?
            "credit"
          elsif org.payment_method&.paypal_email.present?
            "paypal"
          else
            "none"
          end
        end
      end
    end
  end
end
