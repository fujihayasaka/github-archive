# frozen_string_literal: true

require "github_helpers"
require "renderer"

module Middlewares
  class CheckGitHubWebhookSignature < Coach::Middleware
    def call
      return invalid_signature_error unless signature_matches?

      next_middleware.call
    end

    private

    def signature_matches?
      Rack::Utils.secure_compare(expected_signature, webhook_signature)
    end

    def invalid_signature_error
      Renderer.render_error(
        status: 403,
        title: "Forbidden",
        detail: "Invalid signature",
      )
    end

    def expected_signature
      GitHubHelpers.webhook_signature(request_body, webhook_secret)
    end

    def webhook_signature
      request.headers.fetch("X-Hub-Signature", "")
    end

    def webhook_secret
      Prius.get(:github_integration_webhook_secret)
    end

    def request_body
      @request_body ||=
        begin
          request.body.rewind
          request.body.read
        end

      request.body.rewind
      @request_body
    end
  end
end
