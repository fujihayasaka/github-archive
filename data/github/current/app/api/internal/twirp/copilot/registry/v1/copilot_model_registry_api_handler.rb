# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-registry"

module Api::Internal::Twirp::Copilot
  module Registry
    module V1
      class CopilotModelRegistryApiHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Copilot::Helpers

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped],
            env: T::Hash[T.untyped, T.untyped],
          ).void
        end
        def before_rpc(rack_env, env)
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
          env[:internal_client_id] = rack_env[:internal_client_id]
          env[:real_ip]            = rack_env["HTTP_X_CLIENT_IP"]
          env[:request_id]         = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
        end

        allow_access_for :client, allowed_clients: %w[
          copilot_model_registry
        ]
        handles_service MonolithTwirp::Copilot::Registry::V1::CopilotRegistryAPIClient

        resolve_tenant_context only: [
          :get_models,
        ] do |_data, _env|
          # Need to fix this part up
          next
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Registry::V1::GetModelsRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
              Twirp::Error,
            )
          )
        end
        def get_models(req, env)
          {}
        end
      end
    end
  end
end
