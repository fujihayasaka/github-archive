# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-token"

module Api::Internal::Twirp::Copilot
  module Token
    module V1
      # Handler for the MonolithTwirp::Copilot::Token::V1::CopilotTokenServiceAPIService
      class CopilotTokenServiceAPIHandler < Api::Internal::Twirp::Handler
        include App::IExecContextAccessor
        include Platform::Authorization

        allow_access_for :client, allowed_clients: ["copilot_token_service"]
        handles_service MonolithTwirp::Copilot::Token::V1::CopilotTokenServiceAPIService

        sig { params(rack_env: T.untyped, env: T.untyped).void }
        def before_rpc(rack_env, env)
          env[:asn] = rack_env["HTTP_X_AS"]
          env[:real_ip] = rack_env["HTTP_X_REAL_IP"]
          env[:editor_plugin_version] = rack_env["HTTP_EDITOR_PLUGIN_VERSION"]
          env[:editor_version] = rack_env["HTTP_EDITOR_VERSION"]
          env[:github_api_version] = rack_env["HTTP_X_GITHUB_API_VERSION"]
          env[:api_remote_ip] = rack_env["api.remote_ip"]
          env[:github_request_id] = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
          env[:user_agent] = rack_env["HTTP_USER_AGENT"]
        end

        # Public: Implementation of the GetToken Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilot::Token::V1::GetTokenRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Copilot::Token::V1::GetTokenResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilot::Token::V1::GetTokenRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(MonolithTwirp::Copilot::Token::V1::GetTokenResponse, Twirp::Error))
        end
        def get_token(req, env)
          requesting_user = get_requesting_user(req, env)
          return Twirp::Error.permission_denied("invalid user") if requesting_user.nil?

          return Twirp::Error.permission_denied("permission denied") unless user_can_access(requesting_user, req.user_id != 0)

          copilot_user = Copilot::User.new(requesting_user)
          headers = copilot_headers(req, env)

          authorizer = Copilot::Authorizer.new(
            copilot_user,
            GitHub.context,
            headers,
            include_snippy: true,
          )

          return Twirp::Error.permission_denied("permission denied") if GitHub.multi_tenant_enterprise? && authorizer.has_cfi_access?

          if authorizer.access_allowed?
            # If we have any payment method auth checks that are pending_token, we need to flip those to active
            if requesting_user.feature_flag_enabled?(:copilot_business_secondary_auth_check, default: false) && copilot_user.has_pending_auth_checks?
              ActiveRecord::Base.connected_to(role: :writing) do
                copilot_user.activate_pending_auth_checks!
              end
            end

            # if this is a Seat Assignment, we need to make sure to convert it to Seats
            if authorizer.access_type.to_s.include?("SEAT_ASSIGNMENT")
              GitHub.logger.info("Triggering seat assignment conversion", "gh.user.id" => requesting_user.id)
              Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
                user_id: requesting_user.id,
                headers: headers,
              )
            end

            # moving the envelope down here because we want to check the ip first up there
            envelope = Copilot::Envelope.new(authorizer, headers, cap_filter)
            Copilot::Instrumenter.instrument_token_generated(
              copilot_user,
              -1,
              authorizer.access_type,
              headers,
              authorizer.organization_list,
              source: "twirp_get_token",
            )
            env_hash = envelope.envelope.with_indifferent_access # expected hash-like
            # Hardcoded field extraction (string or symbol keys tolerated)
            # Normalize endpoints sub-hash so proto field names with underscores are used instead of dashes
            raw_endpoints = env_hash[:endpoints]
            endpoints_msg = T.let(nil, T.nilable(MonolithTwirp::Copilot::Token::V1::Endpoints))
            if raw_endpoints.is_a?(Hash)
              allowed_endpoint_fields = %w[api origin_tracker proxy telemetry]
              mapped = raw_endpoints.each_with_object({}) do |(k, v), h|
                key = k.to_s.tr("-", "_")
                next unless allowed_endpoint_fields.include?(key)
                h[key.to_sym] = v
              end
              endpoints_msg = MonolithTwirp::Copilot::Token::V1::Endpoints.new(**mapped)
            end

            MonolithTwirp::Copilot::Token::V1::GetTokenResponse.new(
              annotations_enabled:           env_hash[:annotations_enabled],
              blackbird_clientside_indexing: env_hash[:blackbird_clientside_indexing],
              chat_enabled:                  env_hash[:chat_enabled],
              chat_jetbrains_enabled:        env_hash[:chat_jetbrains_enabled],
              code_quote_enabled:            env_hash[:code_quote_enabled],
              code_review_enabled:           env_hash[:code_review_enabled],
              codesearch:                    env_hash[:codesearch],
              copilotignore_enabled:         env_hash[:copilotignore_enabled],
              endpoints:                     endpoints_msg,
              enterprise_list:               env_hash[:enterprise_list],
              expires_at:                    env_hash[:expires_at],
              individual:                    env_hash[:individual],
              limited_user_quotas:           env_hash[:limited_user_quotas],
              limited_user_reset_date:       env_hash[:limited_user_reset_date],
              organization_list:             env_hash[:organization_list],
              prompt_8k:                     env_hash[:prompt_8k],
              public_suggestions:            env_hash[:public_suggestions],
              refresh_in:                    env_hash[:refresh_in],
              sku:                           env_hash[:sku],
              snippy_load_test_enabled:      env_hash[:snippy_load_test_enabled],
              telemetry:                     env_hash[:telemetry],
              token:                         env_hash[:token],
              tracking_id:                   env_hash[:tracking_id],
              vsc_electron_fetcher_v2:       env_hash[:vsc_electron_fetcher_v2],
              xcode:                         env_hash[:xcode],
              xcode_chat:                    env_hash[:xcode_chat],
            )
          else
            # moving the envelope down here because we want to check the ip first up there
            envelope = Copilot::Envelope.new(authorizer, headers)
            envelope.instrument_token_failure(authorizer.reason, headers)
            # TODO: original returned 403 with the "token" - but is that even possible for twirp?
            Twirp::Error.permission_denied("permission denied")
          end
        rescue StandardError => e # rubocop:todo Lint/RescueException
          copilot_error = Copilot::Errors::TokenFailureError.from_error(e)
          Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
          Copilot::Instrumenter.instrument_token_failed(Copilot::User.new(T.must(requesting_user)), "server_error", copilot_headers(req, env))

          Twirp::Error.permission_denied("resource not accessible by integration, contact support: #{Copilot::Envelope::SUPPORT_PAGE}")
        end

        private

        sig { override.returns(App::IContext) }
        def exec_context
          App::SimpleContext.new
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::Token::V1::GetTokenRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T::Hash[Symbol, String])
        end
        def copilot_headers(req, env)
          editor_version = req.editor_version.present? ? req.editor_version : env[:editor_version].to_s
          editor_plugin_version = req.plugin_version.present? ? req.plugin_version : env[:editor_plugin_version].to_s
          user_agent = env[:user_agent].to_s

          log_headers(env, editor_version, editor_plugin_version) if editor_version.blank? && editor_plugin_version.blank? && user_agent.present?

          {
            asn: req.asn.present? ? req.asn : env[:asn].to_s,
            editor_plugin_version: editor_plugin_version,
            editor_version: editor_version,
            github_api_version: env[:github_api_version].to_s,
            ip_address: env[:api_remote_ip].to_s,
            real_ip: req.real_ip.present? ? req.real_ip : env[:real_ip].to_s,
            request_id: env[:github_request_id].to_s,
            user_agent: user_agent.to_s,
          }
        end

        sig { params(env: T::Hash[T.untyped, T.untyped], editor_version: String, editor_plugin_version: String).void }
        def log_headers(env, editor_version, editor_plugin_version)
          GitHub.dogstats.increment("copilot.authorizer.editor_version_missing")
          keys = env.keys.map(&:to_s).select do |key|
            # check if key is all caps and has a dash
            key.match?(/\A[A-Z_\-]+\z/)
          end.sort

          GitHub.logger.info(
            "Editor version and plugin version are missing",
            "gh.copilot.request_keys" => keys,
            "gh.copilot.editor_version" => editor_version,
            "gh.copilot.editor_plugin_version" => editor_plugin_version,
            "gh.copilot.user_agent" => env[:user_agent].to_s,
          )
        end

        sig { params(req: MonolithTwirp::Copilot::Token::V1::GetTokenRequest, env: T::Hash[Symbol, T.untyped]).returns(T.nilable(User)) }
        def get_requesting_user(req, env)
          remote_ip = req.real_ip.present? ? req.real_ip : (env[:HTTP_X_REAL_IP] || env[:real_ip])

          # First attempt to find user by user_id if provided
          if req.user_id != 0
            User.find_by(id: req.user_id)
          else
            # Otherwise, authenticate the user via the provided GitHub token
            api_auth = GitHub::Authentication::Attempt.new(
              allow_integrations:                 false,
              allow_user_via_granular_actor:      true,
              from:                               :internal_api,
              token:                              req.gh_token,
              ip:                                 remote_ip,
              user_agent:                         env[:user_agent],
              request_id:                         env[:request_id],
              password_auth_blocked:              true,
              url:                                env[:path],
            )

            api_auth.result.user
          end
        end

        # TODO: Implement parity for control_access
        sig { params(user: User, user_id_provided: T::Boolean).returns(T::Boolean) }
        def user_can_access(user, user_id_provided)
          return false unless user.feature_flag_enabled?(:copilot_token_twirp, default: false)

          return false unless GitHub.copilot_enabled?

          # If user_id was provided, we skip the app permission check - authnd already happened from the caller
          return true if user_id_provided

          app = Api::AccessControl.current_app_for(user)

          # authentication only happens in app context - we won't bother to instrument this
          return false unless app

          return false unless ::Apps::Privileged.capable?(:generate_copilot_cdn_token, app: app)

          true
        end
      end
    end
  end
end
