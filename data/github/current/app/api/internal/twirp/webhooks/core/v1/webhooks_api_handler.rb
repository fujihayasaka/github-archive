# typed: true
# frozen_string_literal: true

require "monolith-twirp-webhooks-core"

module Api::Internal::Twirp::Webhooks
  module Core
    module V1
      # Handler for the MonolithTwirp::Webhooks::Core::V1::WebhooksAPIService
      class WebhooksAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["webhooks"]
        connected_to_writing_for :delete_cli_hook
        handles_service MonolithTwirp::Webhooks::Core::V1::WebhooksAPIService

        # Public: Implementation of the AuthorizeCliForward Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Webhooks::Core::V1::AuthorizeCliForwardRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Webhooks::Core::V1::AuthorizeCliForwardResponse, or a Twirp::Error.
        def authorize_cli_forward(req, env)
          if req.token == ""
            return Twirp::Error.invalid_argument("missing token in request", argument: "token")
          end
          if req.hook_id == ""
            return Twirp::Error.invalid_argument("missing hook_id in request", argument: "hook_id")
          end
          api_auth = GitHub::Authentication::Attempt.new(
            allow_user_via_granular_actor: true,
            from: :internal_api,
            token: req.token,
            password_auth_blocked: true,
            url: "/internal/twirp/github.webhooks.core.v1.WebhooksAPI/AuthorizeCliForward",
          )
          result = api_auth.result
          unless result.success?
            return { authorized: false }
          end
          hook = Hook.find_by(id: req.hook_id)
          if hook.nil?
            return Twirp::Error.not_found("hook not found")
          end
          {
            authorized: hook.name == "cli" && T.must(hook.creator).id == result.user.id,
            login: result.user.login,
          }
        end

        # req - The Twirp request as a MonolithTwirp::Webhooks::Core::V1::DeleteCliHookRequest.
        # env - The Twirp environment as a Hash.
        def delete_cli_hook(req, env)
          if req.hook_id == ""
            return Twirp::Error.invalid_argument("missing hook_id in request", argument: "hook_id")
          end

          hook = Hook.find_by(id: req.hook_id)
          if hook.nil?
            return {}
          end
          if hook.name != "cli"
            return Twirp::Error.invalid_argument("hook is not a cli hook", argument: "hook_id")
          end

          hook.destroy!
          {}
        end
      end
    end
  end
end
