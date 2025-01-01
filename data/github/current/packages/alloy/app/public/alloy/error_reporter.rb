# typed: strict
# frozen_string_literal: true

module Alloy
  class ErrorReporter
    @@error_reporter = T.let(
      GitHub::JavaScriptErrorReporter.new(
        serviceowners: GitHub.serviceowners,
        allow_all_errors: true
      ),
      GitHub::JavaScriptErrorReporter
    )

    sig { params(error: String, url: T.nilable(String), sanitized_url: T.nilable(String), user: T.nilable(User), bundler: T.nilable(Symbol)).void }
    def report(error:, url:, sanitized_url:, user:, bundler:)
      parsed_error = begin
        expand_stacktrace(JSON.parse(error, symbolize_names: true))
      rescue JSON::ParserError
        { value: error }
      end

      error_reporter.report({
        user_agent: "Alloy",
        error: parsed_error,
        url: url,
        sanitized_url: sanitized_url,
        user: user,
        bundler: bundler
      })
    end

    private

    sig { params(error: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def expand_stacktrace(error)
      error[:stacktrace]&.each do |frame|
        next if frame[:filename].blank? || frame[:filename].include?(GitHub.asset_host_url.presence || GitHub.url)

        frame[:filename] = "#{GitHub.asset_host_url.presence || GitHub.url}/assets/#{frame[:filename]}"
      end

      error
    end

    sig { returns(GitHub::JavaScriptErrorReporter) }
    def error_reporter
      @@error_reporter
    end
  end
end
