# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-token"

module Api::Internal::Twirp::Copilot
  module Token
    module V1
      class CopilotTokenServiceEnvelopeApiHandler < Api::Internal::Twirp::Handler

        allow_access_for :client, allowed_clients: ["copilot_token_service"]
        handles_service MonolithTwirp::Copilot::Token::V1::CopilotTokenServiceEnvelopeAPIService

        sig do
          params(
            req: MonolithTwirp::Copilot::Token::V1::BuildEnvelopeRequest,
            env: T::Hash[Symbol, T.untyped],
          ).returns(MonolithTwirp::Copilot::Token::V1::BuildEnvelopeResponse)
        end
        def build_envelope(req, env)
          # TODO: replace headers from PB
          requesting_user = User.find_by(id: req.user_id)
          return Twirp::Error.permission_denied("invalid user") if requesting_user.nil?

          return Twirp::Error.permission_denied("permission denied") unless requesting_user.feature_flag_enabled?(
            :copilot_token_service_m4_extraction, default: false
          )

          # If we got to this point, we can assume that CTS / dotcom authorizers have confirmed access for this user
          copilot_user = Copilot::User.new(requesting_user)
          envelope_builder = T.must(req.envelope_builder)

          # ... unless for some weird reason the authorizer decided to deny access and we got here, sanity check
          return Twirp::Error.permission_denied("authorizer denied user") unless
            T.must(envelope_builder.authorizer_decision).access_allowed

          # Try to build the envelope
          envelope = Copilot::EnvelopeExtracted.new(nil, Hash.new, nil, nil, envelope_builder, copilot_user)
          env_hash = envelope.envelope.with_indifferent_access # expected hash-like
          # Instrumentation should happen in CTS

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

          # TODO: convert to GetTokenResponses after we've confirmed we have all the data needed E2E
          completed_envelope = MonolithTwirp::Copilot::Token::V1::EnvelopeBuilder.new(
              annotations_enabled:           env_hash[:annotations_enabled],
              blackbird_clientside_indexing: env_hash[:blackbird_clientside_indexing],
              chat_enabled:                  env_hash[:chat_enabled],
              chat_jetbrains_enabled:        env_hash[:chat_jetbrains_enabled],
              code_quote_enabled:            env_hash[:code_quote_enabled],
              code_review_enabled:           env_hash[:code_review_enabled],
              codesearch:                    env_hash[:codesearch],
              copilotignore_enabled:         env_hash[:copilotignore_enabled],
              endpoints:                     endpoints_msg,
              enterprise_list:               env_hash[:enterprise_list].map(&:to_i), # TODO: We should standardize the typing across PBs to stringify
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
              token:                         env_hash[:token],  # THIS IS UNSIGNED, CTS WILL HMAC SIGN
              tracking_id:                   env_hash[:tracking_id],
              vsc_electron_fetcher_v2:       env_hash[:vsc_electron_fetcher_v2],
              xcode:                         env_hash[:xcode],
              xcode_chat:                    env_hash[:xcode_chat],
          )
          MonolithTwirp::Copilot::Token::V1::BuildEnvelopeResponse.new(
            envelope_builder: completed_envelope,
            envelope_complete: true,
            user_id: req.user_id,
          )
        rescue StandardError => e
          copilot_error = Copilot::Errors::TokenFailureError.from_error(e)
          Copilot::Instrumenter.instrument_token_failed(
            T.must(copilot_user),
            "server_error",
            Hash.new,
          )
          Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)

          Twirp::Error.internal("failed to execute envelope builder: #{e.message}")
        end
      end
    end
  end
end
