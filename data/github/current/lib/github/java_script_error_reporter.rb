# typed: true
# frozen_string_literal: true

require "browser"

module GitHub
  class JavaScriptErrorReporter
    ORG_PROJECT_URL_REGEX = /\Ahttps?\:\/\/[^\/]+\/orgs\/(?<org_login>[^\/]+)\/projects/.freeze
    TOKEN_REGEX = OauthAccessTokens::Domain.token_regex.freeze

    # Create an error stack trace reporter.
    #
    # serviceowners - The GitHub::Serviceowners matching services to source files.
    # resolver - The GitHub::SourceMapResolver to map stack traces to source files.
    #
    # Examples
    #
    #   resolver = GitHub::SourceMapResolver.new("public/assets")
    #   reporter = GitHub::JavaScriptErrorReporter.new(serviceowners: Serviceowners.new, resolver: resolver)
    #   reporter.report(error)
    sig  { params(serviceowners: T.nilable(GitHub::Serviceowners), resolver: T.any(GitHub::SourceMapResolver, Alloy::SourceMapResolver)).void }
    def initialize(serviceowners:, resolver:)
      @serviceowners = serviceowners
      @resolver = resolver
    end

    # Sends the JavaScript exception to failbot.
    #
    # input - A Hash of exception data from Platform::Mutations::ReportBrowserError.
    #
    # Returns nothing.
    def report(input)
      return if bot?(input[:user_agent])

      error = input[:error]
      return unless error && reportable?(error)

      if is_webpack_loader_error?(error)
        tags = get_tags_for_webpack_loader(error)
        GitHub.dogstats.increment("browser.bundle_failures", tags: tags)
        return
      end

      react_app_name = input[:react_app_name]
      critical = input.fetch(:critical, false)
      if critical && react_app_name
        GitHub.dogstats.increment(
          "browser.critical_react_error",
          tags: ["react.app_name:#{react_app_name}"],
        )
      end

      catalog_service = service_from_error(error)

      detail = {
        type: error[:type],
        value: sanitize_value(error[:value]),
        stacktrace: error[:stacktrace].reverse,
      }

      context = {
        app: "github-js",
        platform: "javascript",
        sanitized_url: input[:sanitized_url],
        referrer: input[:referrer],
        user_agent: input[:user_agent],
        time_since_load: input[:time_since_load],
        "#turbo": input[:turbo],
        "#ui": input[:ui],
        user: input[:user],
        ready_state: input[:ready_state],
        "#bundler": input[:bundler],
        exception_detail: [detail],
        catalog_service: catalog_service,
        rollup: "auto",
        critical:,
        "#react.app_name": react_app_name,
        "#gh.actor.id": input[:actor_id]
      }

      Failbot.report!(Api::JavaScriptError.new(error), context)
    end

    private

    def sanitize_value(value)
      value.gsub(TOKEN_REGEX, "<redacted>")
    end

    def bot?(user_agent)
      user_agent.blank? || Browser.new(user_agent).bot?
    end

    def is_webpack_loader_error?(error)
      error[:type] == "ChunkLoadError" && match_webpack_loader_error(error)
    end

    def match_webpack_loader_error(error)
      error[:value].match(/\ALoading chunk (.*) failed/)
    end

    def get_tags_for_webpack_loader(error)
      tags = ["bundler:webpack"]
      match = match_webpack_loader_error(error)
      if match
        tags << "chunk:#{match[1]}"
      else
        tags << "chunk:unknown"
      end
      tags
    end

    def reportable?(error)
      required = error.values_at(:type, :value, :stacktrace).none? { |x| x.nil? || x.empty? }
      required && @resolver.stacktrace?(error)
    end

    def service_from_error(error)
      if service = error[:catalog_service]
        return GitHub::Serviceowners::UNKNOWN_SERVICE if service == "*"
        return service if service.start_with?("github/")
        return "github/#{service}"
      end
      service_from_stacktrace(error[:stacktrace])
    end

    # Finds the service for the file in the first non-node_module frame of the exception's
    # stack trace. Maintainers of this service are most likely to know how to fix
    # the error, although it could be caused deeper in the stack.
    #
    # stacktrace - Array<{filename: String, lineno: Integer, colno: Integer}>
    #
    # Returns a String service names.
    def service_from_stacktrace(stacktrace)
      catalog_service = if @serviceowners && file = resolve(stacktrace)
        @serviceowners.service_for_path(file, prefix: true)
      end
      catalog_service ||= GitHub::Serviceowners::UNKNOWN_SERVICE
    end

    # Iterate through a stack trace, eagerly resolving the first non-node_modules file.
    # This is a best effort attempt to find the file that caused the error.
    # If no file is found, the first file in the stack trace is returned instead.
    #
    # stacktrace - Array<{filename: String, lineno: Integer, colno: Integer}>
    #
    # Returns a String file name.
    def resolve(stacktrace)
      first_match = T.let(nil, T.nilable(String))

      stacktrace.each do |frame|
        url, line, col = frame.values_at(:filename, :lineno, :colno)
        resolved_source_file = @resolver.resolve(url: url, line: line.to_i, column: col.to_i)

        first_match ||= resolved_source_file

        next if resolved_source_file == ""
        next if resolved_source_file&.start_with?("node_modules", "/node_modules")

        return resolved_source_file if resolved_source_file
      end

      first_match
    end
  end
end
