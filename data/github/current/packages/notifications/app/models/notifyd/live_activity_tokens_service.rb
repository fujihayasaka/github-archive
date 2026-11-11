# typed: true
# frozen_string_literal: true

module Notifyd
  class LiveActivityTokensService
    include Notifyd::NetworkHelper

    # Create or update a push-to-start iOS Live Activities token.
    sig do
      params(
        user_id: Integer,
        device_token: String,
        live_activity_type: String,
        token: String
      ).returns(T.nilable(T::Boolean))
    end
    def self.set_start_token(user_id:, device_token:, live_activity_type:, token:)
      request = Notifyd::Proto::LiveActivityTokens::SetStartTokenRequest.new(
        user_id: user_id,
        device_token: device_token,
        live_activity_type: live_activity_type,
        token: token
      )

      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request.class.name.to_s }) do
        response = ResponseHandler.new(request_class_name: request.class.name, raise_error: false, tags: []).execute do
          Notifyd.client&.live_activity_tokens&.set_start_token(request)
        end
        return nil unless response.present?
        # Data should be a BooleanValue but the default value (false) is omitted, resulting in nil data in that case.
        return false unless response.data
        response.data.value
      end
    end

    # Create a push iOS Live Activities token.
    sig do
      params(
        device_token: String,
        live_activity_type: String,
        session_id: String,
        token: String,
        user_id: Integer
      ).returns(T.nilable(T::Boolean))
    end
    def self.set_push_token(device_token:, live_activity_type:, session_id:, token:, user_id:)
      request = Notifyd::Proto::LiveActivityTokens::SetPushTokenRequest.new(
        device_token: device_token,
        live_activity_type: live_activity_type,
        session_id: session_id,
        token: token,
        user_id: user_id
      )

      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request.class.name.to_s }) do
        response = ResponseHandler.new(request_class_name: request.class.name, raise_error: false, tags: []).execute do
          Notifyd.client&.live_activity_tokens&.set_push_token(request)
        end

        return nil unless response.present?
        # Data should be a BooleanValue but the default value (false) is omitted, resulting in nil data in that case.
        return false unless response.data
        response.data.value
      end
    end
  end
end
