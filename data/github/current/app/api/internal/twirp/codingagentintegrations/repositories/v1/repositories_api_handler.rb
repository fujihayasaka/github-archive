# typed: true
# frozen_string_literal: true

require "monolith-twirp-codingagentintegrations-repositories"

module Api::Internal::Twirp::Codingagentintegrations
  module Repositories
    module V1
      # Handler for the CodingAgentIntegrations Repositories API.
      #
      # Provides RPCs for checking whether a repository is covered by a
      # Copilot for Jira GitHub App installation and whether that installation
      # is in a caller-provided allow list.
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["coding_agent_integrations"]
        handles_service MonolithTwirp::CodingAgentIntegrations::Repositories::V1::RepositoriesAPIService

        # Public: Implementation of the CheckRepositoryInstallation Twirp RPC.
        #
        # Given a repository NWO and a list of app installation IDs, checks
        # whether the Copilot for Jira GitHub App is installed on the
        # repository and whether the installation ID is in the provided list.
        #
        # req - The Twirp request as a
        #   MonolithTwirp::CodingAgentIntegrations::Repositories::V1::CheckRepositoryInstallationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        #   MonolithTwirp::CodingAgentIntegrations::Repositories::V1::CheckRepositoryInstallationResponse,
        #   or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodingAgentIntegrations::Repositories::V1::CheckRepositoryInstallationRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[Symbol, T.untyped],
              Twirp::Error
            )
          )
        end
        def check_repository_installation(req, env)
          repository_nwo = req.repository_nwo
          if repository_nwo.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_nwo")
          end

          app_installation_ids = req.app_installation_ids.to_a
          if app_installation_ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "app_installation_ids")
          end

          repository = Repository.nwo(repository_nwo)
          if repository.nil?
            return Twirp::Error.not_found("repository not found", argument: "repository_nwo")
          end

          integration = Apps::Privileged.integration(:copilot_jira)
          if integration.nil?
            return Twirp::Error.internal("Copilot for Jira integration not configured")
          end

          installation = IntegrationInstallation.with_repository(repository).find_by(integration: integration)

          if installation.nil?
            return {
              status: :CHECK_REPOSITORY_INSTALLATION_STATUS_NOT_INSTALLED,
              installation_id: 0,
            }
          end

          if app_installation_ids.include?(installation.id)
            {
              status: :CHECK_REPOSITORY_INSTALLATION_STATUS_INSTALLED_AND_ALLOWED,
              installation_id: installation.id,
            }
          else
            {
              status: :CHECK_REPOSITORY_INSTALLATION_STATUS_INSTALLED_NOT_IN_LIST,
              installation_id: installation.id,
            }
          end
        end
      end
    end
  end
end
