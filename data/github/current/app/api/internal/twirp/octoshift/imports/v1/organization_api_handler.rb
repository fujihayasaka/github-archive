# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Provides access to Organization data.
      class OrganizationAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::OrganizationAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the GetOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::GetOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::GetOrganizationResponse, or a Twirp::Error.
        def get_organization(req, env)
          if req.login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "login")
          end

          organization = replica(Organization).find_by(login: req.login)
          return Twirp::Error.not_found("organization not found", argument: "login") unless organization

          build_organization_hash(organization)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        # Private: Convert the organization object to the Twirp response
        # GetOrganizationResponse.
        #
        # organization - The organization object.
        #
        # Returns an Hash object with organization data that matches the
        # Twirp definition.
        def build_organization_hash(organization)
          {
            id: organization.id,
            name: organization.name,
            login: organization.login,
            business_slug: organization&.business&.slug
          }
        end
      end
    end
  end
end
