# typed: true
# frozen_string_literal: true

module Notifyd
  class DeviceTokensService
    include Notifyd::NetworkHelper

    # Create or update a device token.
    # On success a boolean is returned indicating whether the token was created / updated or not
    # (a new device may fail if the limit of tokens per user is reached).
    # Nil is returned if there's an error processing the request.
    sig { params(user_id: Integer, oauth_access_id: Integer, token: String).returns(T.nilable(T::Boolean)) }
    def self.set(user_id:, oauth_access_id:, token:)
      request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id:, oauth_access_id:, token:)
      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request.class.name.to_s }) do
        response = ResponseHandler.new(request_class_name: request.class.name, raise_error: false, tags: []).execute do
          Notifyd.client&.device_tokens_v2.set(request)
        end
        return nil unless response.present?
        # Data should be a BooleanValue but the default value (false) is omitted, resulting in nil data in that case.
        return false unless response.data
        response.data.value
      end
    end

    # Delete a user device token. True is returned on success, false otherwise.
    # Attempting to delete a non-existent token will succeed, making the operation idempotent.
    sig { params(user_id: Integer, token: String).returns(T::Boolean) }
    def self.delete(user_id:, token:)
      request = Notifyd::Proto::DeviceTokensV2::DeleteRequest.new(user_id:, token:)
      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request.class.name.to_s }) do
        response = ResponseHandler.new(request_class_name: request.class.name, raise_error: false, tags: []).execute do
          Notifyd.client&.device_tokens_v2.delete(request)
        end
        response.present?
      end
    end

    # Delete all the user device tokens. True is returned on success, false otherwise.
    sig { params(user_id: Integer).returns(T::Boolean) }
    def self.delete_all(user_id:)
      request = Notifyd::Proto::DeviceTokensV2::DeleteAllRequest.new(user_id:)
      GitHub.tracer.in_span("notifyd.network_helper", kind: :internal, attributes: { "code.namespace" => request.class.name.to_s }) do
        response = ResponseHandler.new(request_class_name: request.class.name, raise_error: false, tags: []).execute do
          Notifyd.client&.device_tokens_v2.delete_all(request)
        end
        response.present?
      end
    end
  end
end
