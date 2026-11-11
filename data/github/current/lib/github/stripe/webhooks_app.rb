# typed: true
# frozen_string_literal: true

module GitHub
  module Stripe
    class WebhooksApp
      HEADERS = { "Content-Type" => "text/plain" }
      EMPTY_RESPONSE = []

      def self.call(env)
        new(env).call
      end

      attr_reader :request

      def initialize(env)
        @env = env
        @request = Rack::Request.new(env)
      end

      def call
        return method_not_allowed_response unless request.post?

        ::Billing::Stripe::WebhookHandler.handle(
          payload: payload,
          signature: signature,
          source: source,
        )
        ok_response
      rescue ActiveRecord::RecordNotUnique => e
        GitHub.dogstats.increment("stripe.webhook.duplicate")
        ok_response
      rescue ::Billing::Stripe::WebhookHandler::InvalidSignature => e
        Failbot.report(e)
        bad_request_response
      end

      private

      def source
        if request.path.include?("connect")
          :connect
        elsif request.path.include?("platform/general")
          :platform_general
        else
          :platform
        end
      end

      def bad_request_response
        [400, HEADERS, EMPTY_RESPONSE]
      end

      def method_not_allowed_response
        [405, HEADERS, EMPTY_RESPONSE]
      end

      def ok_response
        [200, HEADERS, EMPTY_RESPONSE]
      end

      def payload
        @payload ||= request.body.read
      end

      def signature
        @signature ||= request.get_header("HTTP_STRIPE_SIGNATURE")
      end
    end
  end
end
