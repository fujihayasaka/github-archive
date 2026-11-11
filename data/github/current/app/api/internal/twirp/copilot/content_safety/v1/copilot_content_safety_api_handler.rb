# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-content_safety"

module Api::Internal::Twirp::Copilot
  module ContentSafety
    module V1
      class CopilotContentSafetyAPIHandler < Api::Internal::Twirp::Handler
        UserLookupRequest = T.type_alias do
          T.any(
            MonolithTwirp::Copilot::ContentSafety::V1::SetUserMonitoringStateRequest,
            MonolithTwirp::Copilot::ContentSafety::V1::GetUserMonitoringStateRequest,
          )
        end

        TwirpResponse = T.type_alias do
          T.any(
            T::Hash[Symbol, T.untyped],
            Twirp::Error,
          )
        end

        allow_access_for :client, allowed_clients: %w[hamzo copilot_api]

        handles_service MonolithTwirp::Copilot::ContentSafety::V1::CopilotContentSafetyAPIService

        sig { params(req: UserLookupRequest).returns(T.nilable(::User)) }
        def self.find_user(req)
          if req.id.present? && req.id.nonzero?
            ::User.find_by(id: req.id)
          elsif req.analytics_tracking_id.present?
            ::User.find_by(analytics_tracking_id: req.analytics_tracking_id)
          else
            nil
          end
        end
        private_class_method :find_user

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
        end

        resolve_tenant_context only: [
          :set_user_monitoring_state,
          :get_user_monitoring_state,
        ] do |data, _env|
          next find_user(data)&.enterprise_managed_business
        end

        connected_to_writing_for :set_user_monitoring_state, :get_user_monitoring_state

        sig do
          params(
            req: MonolithTwirp::Copilot::ContentSafety::V1::SetUserMonitoringStateRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(TwirpResponse)
        end
        def set_user_monitoring_state(req, env)
          GitHub.dogstats.distribution_time("copilot.twirp.set_user_monitoring_state") do
            result = load_user(req)
            return result.error unless result.ok?
            user = result.value!

            result = ::CopilotContentSafety::MonitoringState.set_from_twirp!(
              user: user,
              monitoring_state: req.monitoring_state,
              client_name: env[:client_name],
              reason: req.reason,
              chat_turn_scan_event_id: req.chat_turn_scan_event_id.presence,
            )
            return result.error unless result.ok?

            result.value!
          end
        end

        sig do
          params(
            req: MonolithTwirp::Copilot::ContentSafety::V1::GetUserMonitoringStateRequest,
            _env: T::Hash[T.untyped, T.untyped],
          ).returns(TwirpResponse)
        end
        def get_user_monitoring_state(req, _env)
          GitHub.dogstats.distribution_time("copilot.twirp.get_user_monitoring_state") do
            result = load_user(req)
            return result.error unless result.ok?
            user = result.value!

            ::CopilotContentSafety::MonitoringState.to_twirp(user: user)
          end
        end

        private

        sig { params(req: UserLookupRequest).returns(GitHub::Result) }
        def load_user(req)
          GitHub.tracer.in_span("copilot.twirp.load_user", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.load_user") do
              user = find_user(req)
              return GitHub::Result.new { user } if user

              if req.id.present? && req.id.nonzero?
                GitHub.dogstats.increment("copilot.twirp.user_not_found")
                GitHub::Result.error(Twirp::Error.not_found("User ID '#{req.id}' not found."))
              elsif req.analytics_tracking_id.present?
                GitHub.dogstats.increment("copilot.twirp.user_not_found")
                GitHub::Result.error(Twirp::Error.not_found("User Analytics ID '#{req.analytics_tracking_id}' not found."))
              else
                GitHub.dogstats.increment("copilot.twirp.no_params")
                GitHub::Result.error(Twirp::Error.invalid_argument("must be provided", argument: "id or analytics_tracking_id"))
              end
            end
          end
        end

        sig { params(req: UserLookupRequest).returns(T.nilable(::User)) }
        def find_user(req)
          self.class.send(:find_user, req)
        end
      end
    end
  end
end
