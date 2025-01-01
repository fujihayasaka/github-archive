# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependency_graph_platform-integrations"

module Api::Internal::Twirp::DependencyGraphPlatform
  module Integrations
    module V1
      class IntegrationsAPIHandler < Api::Internal::Twirp::Handler
        Proto = Github::DependencyGraphPlatform::GhInternal::Integrations::V1

        allow_access_for :client, allowed_clients: ["dependency_graph_platform"]
        handles_service Proto::IntegrationsAPIService

        sig do
          params(
            req: Proto::GetIntegrationsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::GetIntegrationsResponse,
              Twirp::Error
            )
          )
        end
        def get_integrations(req, env)
          response = Proto::GetIntegrationsResponse.new

          code_scanning_integration = ::Apps::Privileged.integration(:code_scanning)
          if code_scanning_integration.present?
            response.code_scanning = proto_integration(code_scanning_integration)
          end

          dependabot_integration = ::Apps::Privileged.integration(:dependabot)
          if dependabot_integration.present?
            response.dependabot = proto_integration(dependabot_integration)
          end

          response
        end

        private

        sig do
          params(integration: ::Integration).returns(Proto::Integration)
        end
        def proto_integration(integration)
          proto = Proto::Integration.new(id: integration.id)
          bot = integration.bot
          if bot.present?
            proto.bot = Proto::Bot.new(
              id: bot.id,
              login: bot.login,
              global_relay_id: bot.global_relay_id
            )
          end
          proto
        end
      end
    end
  end
end
