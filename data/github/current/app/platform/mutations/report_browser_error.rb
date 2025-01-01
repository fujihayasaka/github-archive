# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReportBrowserError < Platform::Mutations::Base
      description "Report browser JavaScript errors to Sentry."

      visibility :internal
      scopeless_tokens_as_minimum
      allow_anonymous_viewer true

      argument :error, Inputs::JavascriptError, "The serialized JavaScript error to report.", required: true
      argument :url, String, "The document URL the error originated from.", required: false
      argument :sanitized_url, String, "The sanitized document URL the error originated from.", required: false
      argument :ready_state, String, "The document readyState when the error was thrown.", required: false
      argument :referrer, String, "The document's previous URL.", required: false
      argument :time_since_load, Integer, "The number of seconds since the page loaded and the error was thrown.", required: false
      argument :user, String, "The current user login.", required: false
      argument :turbo, Boolean, "Whether or not the Turbo feature flag is enabled.", required: false, default_value: false
      argument :ui, Boolean, "Whether the page was loaded by the UI service.", required: false, default_value: false
      argument :bundler, String, "The bundler used to generate client-side assets.", required: false

      def resolve(**inputs)
        inputs[:user_agent] = context[:user_agent]
        inputs[:ip] = context[:real_ip]
        inputs[:error] = inputs[:error].to_h if inputs[:error]
        reporter.report(inputs)
        nil
      end

      private

      def reporter
        @@reporter ||= GitHub::JavaScriptErrorReporter.new(
          resolver: GitHub::SourceMapResolver.new(Rails.root.join("public/assets")),
          serviceowners: GitHub.serviceowners,
        )
      end
    end
  end
end
