# frozen_string_literal: true

require "renderer"

module Routes
  module GitHubWebhooks
    class Create < Coach::Middleware
      include GitHub::Telemetry::Traces::Traceable
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckGitHubWebhookSignature

      def call
        tracer.in_span("#{self.class.name}#call",
                       attributes: { "gh.webhook.event_type" => webhook_action }) do
          return no_webhook_action_error if webhook_action.nil?
          return Renderer.render("pong") if webhook_action == "ping"

          handler = webhook_handler

          if handler
            tracer.in_span("#{handler.class.name}#run") do
              handler.run
            end
            MetricsClient.increment("webhook.handled", tags: { event: webhook_action })
          else
            Rails.logger.info("Ignoring '#{webhook_action}' webhook")
          end

          Renderer.no_content
        end
      end

      private

      def webhook_action
        request.headers["X-GitHub-Event"]
      end

      def webhook_handler
        case webhook_action
        when "issue_comment", "pull_request_review_comment"
          HandleWebhook::IssueComment.new(webhook_body: params, headers: request.headers)
        when "pull_request_review"
          HandleWebhook::PullRequestReview.new(webhook_body: params, headers: request.headers)
        else
          handler_class_name = "HandleWebhook::#{webhook_action.camelize}"
          if Object.const_defined?(handler_class_name)
            handler = Object.const_get(handler_class_name)
            handler.new(webhook_body: params)
          end
        end
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
