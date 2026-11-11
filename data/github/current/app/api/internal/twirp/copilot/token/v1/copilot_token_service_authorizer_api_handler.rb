# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-token"

module Api::Internal::Twirp::Copilot
  module Token
    module V1
      class CopilotTokenServiceAuthorizerApiHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: ["copilot_token_service"]
        handles_service MonolithTwirp::Copilot::Token::V1::CopilotTokenServiceAuthorizerAPIService

        sig { params(rack_env: T.untyped, env: T.untyped).void }
        def before_rpc(rack_env, env)
          # This is fallback and probably dead code
          env[:asn] = rack_env["HTTP_X_AS"]
          env[:real_ip] = rack_env["HTTP_X_REAL_IP"]
          env[:editor_plugin_version] = rack_env["HTTP_EDITOR_PLUGIN_VERSION"]
          env[:editor_version] = rack_env["HTTP_EDITOR_VERSION"]
          env[:github_api_version] = rack_env["HTTP_X_GITHUB_API_VERSION"]
          env[:api_remote_ip] = rack_env["api.remote_ip"]
          env[:github_request_id] = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
          env[:user_agent] = rack_env["HTTP_USER_AGENT"]
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Token::V1::AuthorizeUserRequest,
            env: T::Hash[Symbol, T.untyped],
          ).returns(MonolithTwirp::Copilot::Token::V1::AuthorizeUserResponse)
        end
        def authorize_user(req, env)
          # Request should have been validated by authnd already
          requesting_user = User.find_by(id: req.user_id)
          return Twirp::Error.permission_denied("invalid user") if requesting_user.nil?

          return Twirp::Error.permission_denied("permission denied") unless requesting_user.feature_flag_enabled?(
            :copilot_token_service_m4_extraction, default: false
          )

          copilot_user = Copilot::User.new(requesting_user)
          authorizer_session = T.must(req.authorizer_session)
          authorizer = Copilot::AuthorizerExtracted.new(
            copilot_user,
            authorizer_session,
            GitHub.context,
            authorizer_session.copilot_headers&.to_h || {},
            include_snippy: true,
          )

          # TODO: figure out what has_cfi_access? is and extract: https://github.com/github/copilot-business-org/issues/428
          # This will check if the user has access, skipping any checks already done in the authorizer_session
          has_cfi_access = authorizer.has_cfi_access?
          authorizer_session.has_cfi_access = has_cfi_access
          authorizer_session.access_allowed = T.must(
            !(GitHub.multi_tenant_enterprise? && has_cfi_access) &&
            authorizer.access_allowed?
          )
          authorizer_session.authorative_access_type = T.must(
            MonolithTwirp::Copilot::Token::V1::AccessType.resolve(:"ACCESS_TYPE_#{authorizer.access_type}")
          )

          # TODO: I think we want to return the AuthorizerDecision at some point, but we'll keep the session for
          # flexibility while we do initial testing
          MonolithTwirp::Copilot::Token::V1::AuthorizeUserResponse.new(
            user_id: req.user_id,
            authorizer_session: authorizer_session,
            authorization_complete: true,
          )
        rescue StandardError => e
          copilot_error = Copilot::Errors::TokenFailureError.from_error(e)
          Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
          Copilot::Instrumenter.instrument_token_failed(
            T.must(copilot_user),
            "server_error",
            T.must(authorizer_session).copilot_headers.to_h,
          )

          Twirp::Error.internal("failed to execute authorizer: #{e.message}")
        end
      end
    end
  end
end
