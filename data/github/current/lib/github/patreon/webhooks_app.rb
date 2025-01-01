# typed: true
# frozen_string_literal: true

module GitHub
  module Patreon
    class WebhooksApp
      include GitHub::Memoizer

      HEADERS = { "Content-Type" => "text/plain" }
      EMPTY_RESPONSE = []
      SERVICE_NAME = "github/github_sponsors"

      def self.call(env)
        new(env).call
      end

      def initialize(env)
        @env = env
        @request = Rack::Request.new(env)
        Failbot.push({
          catalog_service: SERVICE_NAME,
          request_id: Rack::RequestId.get(env),
          server_id: Rack::ServerId.get(env),
        })
      end

      def call
        return not_found_response unless GitHub.sponsors_enabled?
        return method_not_allowed_response unless request.post?
        return bad_request_response unless headers?
        Failbot.push(patreon_trigger: trigger)

        PatreonWebhookHandler.call(
          trigger: trigger,
          signature: signature,
          payload: request_body,
        )

        ok_response
      rescue PatreonWebhookHandler::InvalidSignature, PatreonWebhookHandler::InvalidTrigger,
             PatreonWebhookHandler::InvalidPayload, PatreonWebhookHandler::WebhookConfigNotFound => e
        GitHub.logger.error(e.message,
          "gh.catalog_service": SERVICE_NAME,
          "code.namespace": self.class.name,
          "code.function": __method__,
          "patreon.payload": request_body,
          "request.charset": request.content_charset,
          "patreon.signature": signature,
          "patreon.trigger": trigger,
        )
        Failbot.report(e)
        bad_request_response
      rescue PatreonWebhookHandler::ProcessingError => e
        Failbot.report(e)
        unprocessable_entity_response
      end

      private

      sig { returns Rack::Request }
      attr_reader :request

      def ok_response
        [200, HEADERS, EMPTY_RESPONSE]
      end

      def not_found_response
        [404, HEADERS, EMPTY_RESPONSE]
      end

      def method_not_allowed_response
        [405, HEADERS, EMPTY_RESPONSE]
      end

      def bad_request_response
        [400, HEADERS, EMPTY_RESPONSE]
      end

      def unprocessable_entity_response
        [422, HEADERS, EMPTY_RESPONSE]
      end

      sig { returns T.nilable(String) }
      memoize def request_body
        request.body.read
      end

      sig { returns T.nilable(String) }
      memoize def signature
        request.get_header("HTTP_X_PATREON_SIGNATURE")
      end

      sig { returns T.nilable(String) }
      memoize def trigger
        request.get_header("HTTP_X_PATREON_EVENT")
      end

      sig { returns T::Boolean }
      def headers?
        signature.present? && trigger.present?
      end
    end
  end
end
