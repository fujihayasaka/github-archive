# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-tokens"

module Api::Internal::Twirp::Dependabot
  module Tokens
    module V1
      # Handler for MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIService.
      class AppInstallAPIHandler < Api::Internal::Twirp::Handler

        class Error < StandardError
          attr_reader :twirp_error
          def initialize(twirp_error)
            super(twirp_error.msg)
            @twirp_error = twirp_error
          end
        end

        allow_access_for :client, allowed_clients: ["dependabot_api"]
        handles_service MonolithTwirp::Dependabot::Tokens::V1::AppInstallAPIService

        # We only support a subset of possible AutomaticAppInstallation trigger types,
        # this maps the request's enum to the value we sent to the app install.
        SUPPORTED_INSTALL_TRIGGER_TYPES = {
          # TODO: Create a new install trigger?
          #
          # I'm re-using the Dependabot JIT access trigger as this is another JIT use-case,
          # but it might make sense to use separate triggers for clarity in audit logs?
          INSTALL_TRIGGER_DEPENDENCY_GRAPH_REQUESTED: :dependabot_jit_access_requested,
        }.freeze

        resolve_tenant_context do |req, _env|
          repository = ::Repositories::Public.find_active(req.repository_id)
          next repository.owner&.business if repository.present?
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        sig do
          params(
            req: MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallRequest,
            env: T.untyped
          ).returns(
            T.any(
              MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse,
              Twirp::Error
            )
          )
        end
        def create_repository_install(req, env)
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app.blank?

          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?

          install_trigger_type = SUPPORTED_INSTALL_TRIGGER_TYPES[req.trigger]
          return Twirp::Error.invalid_argument("unsupported trigger type", argument: "trigger") unless install_trigger_type

          repository = ::Repository.find_by(id: req.repository_id)

          return Twirp::Error.not_found("Repository ID '#{req.repository_id}' not found.") unless repository

          return MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
            repository_id: req.repository_id,
            state: :INSTALL_STATE_REFUSED_DELETED
          ) if repository.deleted?

          return MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
            repository_id: req.repository_id,
            state: :INSTALL_STATE_REFUSED_ARCHIVED
          ) if repository.archived?

          return MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
            repository_id: req.repository_id,
            state: :INSTALL_STATE_REFUSED_SPAMMY
          ) if repository.spammy?

          if repository.dependabot_installed?
            return MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
              repository_id: req.repository_id,
              state: :INSTALL_STATE_EXISTS,
              installation_id: repository.dependabot_install.id
            )
          end

          installation = install_dependabot_app(repository, install_trigger_type)

          MonolithTwirp::Dependabot::Tokens::V1::CreateRepositoryInstallResponse.new(
            repository_id: req.repository_id,
            state: :INSTALL_STATE_CREATED,
            installation_id: installation.id
          )
        rescue Error => e
          e.twirp_error
        end

        private

        sig do
          params(
            repository: Repository,
            trigger_type: Symbol
          ).returns(IntegrationInstallation)
        end
        def install_dependabot_app(repository, trigger_type)
          result = AutomaticAppInstallation.trigger(
            type: trigger_type,
            originator: { target_id: T.must(repository.owner).id, repository_id: repository.id },
            actor: GitHub.dependabot_github_app_bot,
            async: false,
          ).first

          installation_result = result&.installation_result
          raise Error.new(Twirp::Error.internal("Unexpected install failure", reason: result.reason)) if installation_result.nil?

          if (error = installation_result.exception)
            raise Error.new(
              Twirp::Error.internal("Error while granting permissions",
                error: error.to_s,
                reason: installation_result.reason.to_s
              )
            )
          elsif (reason = installation_result.reason)
            raise Error.new(Twirp::Error.internal("Granting permissions failed", reason: reason.to_s))
          elsif !installation_result.success?
            raise Error.new(Twirp::Error.internal("Granting permissions failed", reason: "unknown"))
          end

          installation_result.installation
        end
      end
    end
  end
end
