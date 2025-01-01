# typed: true
# frozen_string_literal: true

module Alloy
  class ErrorReporter
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

    def expand_stacktrace(error)
      error[:stacktrace]&.each do |frame|
        next if frame[:filename].blank? || frame[:filename].include?(GitHub.asset_host_url.presence || GitHub.url)

        frame[:filename] = "#{GitHub.asset_host_url.presence || GitHub.url}/assets/#{frame[:filename]}"
      end

      error
    end

    sig { returns(GitHub::JavaScriptErrorReporter) }
    def error_reporter
      @@error_reporter ||= GitHub::JavaScriptErrorReporter.new(
        resolver: Alloy::SourceMapResolver.new,
        serviceowners: GitHub.serviceowners,
      )
    end
  end

  class SourceMapResolver
    def resolve(url:, line:, column:)
      url
    end

    def stacktrace?(error)
      true
    end
  end
end
