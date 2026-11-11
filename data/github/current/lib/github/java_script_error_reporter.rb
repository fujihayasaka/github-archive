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
    #
    # Examples
    #
    #   reporter = GitHub::JavaScriptErrorReporter.new(serviceowners: Serviceowners.new)
    #   reporter.report(error)
    sig  { params(serviceowners: T.nilable(GitHub::Serviceowners), allow_all_errors: T::Boolean).void }
    def initialize(serviceowners:, allow_all_errors: false)
      @serviceowners = serviceowners
      @allow_all_errors = allow_all_errors
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

      if service_worker_error?(input)
        tags = get_tags_for_service_worker(error, input)
        GitHub.dogstats.increment("browser.service_worker_error", tags: tags)
      end

      react_app_name = input[:react_app_name]
      react_error_boundary_name = input[:react_error_boundary_name]
      critical = input.fetch(:critical, false)
      ui = !!input.fetch(:ui, false)

      if react_app_name
        react_tags = ["react.app_name:#{react_app_name}"]
        react_tags << "react.error_boundary_name:#{react_error_boundary_name}" if react_error_boundary_name
        react_tags << "ui:#{ui}"

        params = GitHub::BrowserStatsHelper.guess_url_params(input[:sanitized_url])
        if params && !params[:unmatched_route]
          controller = GitHub::TaggingHelper.formatted_controller(params[:controller])
          react_tags << "controller:#{controller}"
          react_tags << "action:#{params[:action]}"
        end

        if critical
          GitHub.dogstats.increment(
            "browser.critical_react_error",
            tags: react_tags,
          )
        end

        GitHub.dogstats.increment(
          "browser.react_error",
          tags: react_tags.append("critical:#{critical}"),
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
        "#react.error_boundary_name": react_error_boundary_name,
        "#gh.actor.id": input[:actor_id],
        "gh.deployment.sha": input[:release],
        release: input[:release],
        past_request_ids: input[:past_request_ids] || [],
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

    def service_worker_error?(input)
      input[:bundler] == "service-worker"
    end

    def get_tags_for_service_worker(error, input)
      ["bundler:service-worker", "error_type:#{error[:type]}", "turbo:#{input[:turbo] || false}"]
    end

    def reportable?(error)
      required = error.values_at(:type, :value, :stacktrace).none? { |x| x.nil? || x.empty? }
      required && stacktrace?(error)
    end

    def stacktrace?(error)
      return true if @allow_all_errors
      error[:stacktrace].any? do |frame|
        frame[:filename].include?(GitHub.asset_host_url.presence || GitHub.url)
      end
    end

    def service_from_error(error)
      if service = error[:catalog_service]
        return GitHub::Serviceowners::UNKNOWN_SERVICE if service == "*"
        return service if service.start_with?("github/")
        return "github/#{service}"
      end

      if error[:catalog_service_hash]
        service_name = T.must(@serviceowners).service_for_hash(error[:catalog_service_hash])
        return service_name if service_name
      end

      GitHub::Serviceowners::UNKNOWN_SERVICE
    end
  end
end
