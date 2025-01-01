# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationAPIService
      class ImportOrganizationAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationAPIService

        # Public: Implementation of the ImportOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationResponse, or a Twirp::Error.
        def import_organization(req, env)
          check_model_replication_delay!(Organization)

          if req.target_enterprise_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "target_enterprise_id")
          end

          if req.target_org_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "target_org_name")
          end

          if req.user_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "user_id")
          end

          user = replica(User).find_by(id: req.user_id)
          unless user
            return Twirp::Error.not_found("user not found.", argument: "user_id", value: req.user_id.to_s)
          end

          enterprise = replica(Business).find_by(id: req.target_enterprise_id)
          unless enterprise
            return Twirp::Error.not_found("enterprise not found.", argument: "target_enterprise_id", value: req.target_enterprise_id.to_s)
          end

          organization = Organization.new(
            login: req.target_org_name.parameterize(preserve_case: true),
            billing_email: user.billing_email,
            admin: user,
            business: enterprise
          )

          if GitHub.multi_tenant_enterprise? && GitHub.flipper[:imported_org_business_id].enabled?
            organization.business_id = enterprise.id
          end

          rate_limited_mode(organization) do
            return save_model_error_handler(organization) unless organization.save
          end

          UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: organization.id)

          enable_sso_if_needed(enterprise, organization, req.target_access_token, user)

          { id: organization.id }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        # Enable SSO for the provided PAT if the enterprise or org has SSO enabled.
        #
        # enterprise - The Enterprise to check for SSO.
        # organization - The Organization to check for SSO and enable SSO for the PAT.
        # pat - The PersonalAccessToken to enable SSO for.
        # user - The User to enable SSO for.
        def enable_sso_if_needed(enterprise, organization, pat, actor)
          # Check if created org has sso enabled or enterprise has sso enabled
          if enterprise.oidc_enabled? || enterprise.saml_sso_enabled? || organization.saml_sso_enabled?

            # Get the credential from the provided PAT
            credential = OauthAccessTokens.domain.active(pat)

            ActiveRecord::Base.connected_to(role: :writing) do
              # Grant SSO access to the pat for the org.
              Organization::CredentialAuthorization.grant(
                organization: organization,
                credential: credential,
                actor: actor
              )
            end
          end
        end
      end
    end
  end
end
