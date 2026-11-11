# frozen_string_literal: true

require "renderer"

# This route is intended to verify we can receive GitHub webhooks without
# fully processing each webhook.  It is intended to be used with a non-production
# GitHub App to test application changes before we apply them to the production
# GitHub App.

module Routes
  module GitHubWebhooks
    class Discard < Coach::Middleware
      include GitHub::Telemetry::Traces::Traceable
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckGitHubWebhookSignature

      def call
        return no_webhook_action_error if webhook_action.nil?

        Rails.logger.info("Log and discard webhook action: #{webhook_action}")
        Renderer.no_content
      end

      private

      def webhook_action
        request.headers["X-GitHub-Event"]
      end

      def no_webhook_action_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "No X-GitHub-Event header provided!",
        )
      end
    end
  end
end
