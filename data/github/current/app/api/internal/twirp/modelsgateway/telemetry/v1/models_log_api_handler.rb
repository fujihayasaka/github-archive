# typed: true
# frozen_string_literal: true

require "monolith-twirp-modelsgateway-telemetry"

module Api::Internal::Twirp::Modelsgateway
  module Telemetry
    module V1
      # Handler for the MonolithTwirp::Modelsgateway::Telemetry::V1::ModelsLogAPIService
      class ModelsLogAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["modelsgateway"]
        handles_service MonolithTwirp::Modelsgateway::Telemetry::V1::ModelsLogAPIService

        # Public: Implementation of the CreateModelsLogEvent Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Modelsgateway::Telemetry::V1::CreateModelsLogEventRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Modelsgateway::Telemetry::V1::CreateModelsLogEventResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Modelsgateway::Telemetry::V1::CreateModelsLogEventRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def create_models_log_event(req, env)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user was not found") unless user

          user_primary_email = T.must(user.primary_user_email).email

          github_models_user = ::GitHubModels::User.new(user: user)
          access_flights = github_models_user.access_flights

          GlobalInstrumenter.instrument("github_models_gateway_log.create", {
            actor: user,
            actor_primary_email: user_primary_email,
            user_agent: req.user_agent,
            model: req.model_name,
            publisher: req.publisher,
            provider: req.provider,
            status_code: req.status_code,
            rate_limit_type: req.rate_limit_type,
            rate_limit_window_seconds: req.rate_limit_window_seconds,
            provider_status_code: req.provider_status_code,
            access_flights: access_flights,
          })

          # TODO: Figure out shape of response
          {}
        end
      end
    end
  end
end
