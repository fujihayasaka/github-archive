# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ValidateSourceCredentialsAPIService.
      class ValidateSourceCredentialsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::ValidateSourceCredentialsAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        def validate_source_credentials(req, env)
          if req.access_token.empty?
            return Twirp::Error.invalid_argument("must not be empty", argument: "access_token")
          end

          if !req.is_org_migration && req.repository_name.empty?
            return Twirp::Error.invalid_argument("must not be empty", argument: "repository_name")
          end

          if req.owner_login.empty?
            return Twirp::Error.invalid_argument("must not be empty", argument: "owner_login")
          end

          owner = replica(Organization).find_by(login: req.owner_login)
          if owner.nil?
            return Twirp::Error.not_found("Organization not found.", argument: "owner_login", value: req.owner_login)
          end

          replica_exists = replica(Repository).query do |klass|
            klass.where(owner: owner, name: req.repository_name).exists?
          end

          if !req.is_org_migration && !replica_exists
            return Twirp::Error.not_found("Repository not found.", argument: "repository_name", value: req.repository_name)
          end

          if legacy_pats_restricted?(owner)
            return Twirp::Error.unauthenticated("Org restricts access via PATs (classic)", octoshift_error_code: "UNAUTHORIZED_CREDENTIALS")
          end

          token = OauthAccessTokens.domain.active(req.access_token)

          unless token
            return Twirp::Error.unauthenticated("Invalid PAT", octoshift_error_code: "UNAUTHORIZED_CREDENTIALS")
          end

          unless pat_can_export_repo?(token, owner)
            return Twirp::Error.unauthenticated("Not authorized to export", octoshift_error_code: "UNAUTHORIZED_CREDENTIALS")
          end

          if pat_needs_sso?(token, owner)
            return Twirp::Error.unauthenticated("PAT needs SSO enabled", octoshift_error_code: "UNAUTHORIZED_CREDENTIALS")
          end

          { can_migrate: true }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def legacy_pats_restricted?(owner)
          owner.legacy_personal_access_tokens_restricted? || owner.business&.legacy_personal_access_tokens_restricted?
        end

        def pat_can_export_repo?(token, owner)
          Octoshift::AuthorizationPolicy.can_export_repo?(user: token.user, owner: owner)
        end

        def pat_needs_sso?(token, owner)
          return false unless owner.saml_sso_enabled? || (owner.business && owner.business.saml_sso_enabled?)

          credential_authorization_exists = replica(Organization::CredentialAuthorization).query do |klass|
            klass.where(
              organization_id: owner.id,
              credential_id: token.id,
              credential_type: "OauthAccess"
            ).exists?
          end

          !token || !credential_authorization_exists
        end
      end
    end
  end
end
