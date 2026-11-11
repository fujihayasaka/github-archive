# typed: true
# frozen_string_literal: true

class Api::BrowserReporting < Api::App
  MAX_BODY_BYTE_SIZE = 1.megabyte

  # DOM sink names reported by browsers in the script-sample field of Trusted Types
  # CSP violations. The format is "ClassName propertyOrMethod"; individual sink
  # names are defined across the spec's integration algorithms (e.g. §4.1.2, §3.8,
  # §4.2.4) rather than in a single table:
  # https://w3c.github.io/trusted-types/dist/spec/
  # Clamped to this set in Datadog tags to control cardinality; the raw value is
  # preserved in the structured log for discovery of new sinks.
  KNOWN_TRUSTED_TYPES_SINKS = Set.new([
    "Element innerHTML",
    "Element outerHTML",
    "Element insertAdjacentHTML",
    "HTMLIFrameElement srcdoc",
    "Range createContextualFragment",
    "document write",
    "document writeln",
    "document open",
    "DOMParser parseFromString",
    "eval",
    "Function",
    "HTMLScriptElement src",
    "HTMLScriptElement text",
    "HTMLScriptElement innerText",
    "HTMLScriptElement textContent",
  ]).freeze

  include GitHub::BrowserStatsHelper

  ErrorsQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: ReportBrowserErrorInput!) {
      reportBrowserError(input: $input)
    }
  GRAPHQL

  before do
    disable_caching!
    disable_hydro_request_logging
    # Still set headers even though we don't apply rate limiting
    custom_throttler = Api::ConfigThrottler.new(
      Api::RateLimitConfiguration.for(Api::RateLimitConfiguration::DEFAULT_FAMILY, self),
      { amount: 0 },
    )
    set_rate_limit!(custom_throttler.check)
  end

  # Do not apply rate limiting to these internal APIs
  rate_limit_as nil

  post "/_private/browser/stats", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/web-systems-reviewers"

    wrap_in_readonly_database do
      begin
        data = receive_with_limits(Hash, required: true, max_byte_size: MAX_BODY_BYTE_SIZE, max_depth: 20)

        target = target_from_data(data)

        GitHub.dogstats.increment("browser.reporting.stats.total", tags: ["target:#{target}"])

        if FeatureFlag.vexi.enabled?(:browser_stats_disabled, default: false)
          deliver_raw("", status: 200, content_type: "text/plain")
          return
        end

        GitHub::BrowserStatsHelper.report_metrics_json(
          data,
          user_agent: GitHub.context[:user_agent],
          ip: GitHub.context[:real_ip],
          snek: request.env["HTTP_X_GITHUB_SNEK"] == "true"
        )
        BrowserStats::DevReporter.new(data).report if Rails.env.development?
      rescue StandardError => error
        GitHub.dogstats.increment("browser.reporting_errors", tags: ["target:#{target}"])
        GitHub.dogstats.increment("browser.reporting.stats.error", tags: ["target:#{target}"])

        GitHub.logger.warn("Browser stats error", {
          "code.namespace": "Api::BrowserReporting",
          "code.function": "stats",
          "exception.message": error.message
        })

        deliver_error!(400)
      end
    end

    deliver_raw("", status: 200, content_type: "text/plain")
  end

  post "/_private/browser/errors", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/web-systems-reviewers"

    wrap_in_readonly_database do
      data = receive_with_limits(max_byte_size: MAX_BODY_BYTE_SIZE, max_depth: 20)

      # Allow backwards compatibility with the old format
      if data.is_a?(Hash) && data["target"]
        error = data["context"]
        target = target_from_data(data)
      else
        error = data
        target = "full"
      end

      tags = ["target:#{target}"]

      GitHub.dogstats.increment("browser.reporting.errors.count", tags: tags)
      if attachment_upload_error?(error)
        GitHub.dogstats.increment("browser.reporting.errors.attachment_upload", tags: tags)
      end

      if !error.is_a?(Hash)
        GitHub.dogstats.increment("browser.reporting.errors.error", tags: tags)
        deliver_error!(400)
      end

      if error["csp-report"]
        policy_enforcement_level = error["csp-report"]["disposition"]
        report_csp_error(error["csp-report"], policy_enforcement_level)
      else
        response = platform_execute(ErrorsQuery, variables: { input: error }, force_readonly: true)
        if response.errors.all.any?
          GitHub.dogstats.increment("browser.reporting.errors.error", tags: tags)
          GitHub.dogstats.increment("browser.reporting_errors", tags: tags)
        end
      end
    end

    deliver_raw("", status: 200, content_type: "text/plain")
  end

  private

  def wrap_in_readonly_database
    ActiveRecord::Base.connected_to(role: :reading) { yield }
  end

  def report_csp_error(report, policy_enforcement_level)
    # We don't care about CSP violations caused by extension scripts.
    if csp_report_noise?(report)
      GitHub.dogstats.increment("content_security_policy", tags: ["error:plugin_noise"])
      return
    end

    document_host = Addressable::URI.parse(report["document-uri"]).host

    # Ignore reports from dynamic labs
    return if GitHub.dynamic_lab_domain?(document_host)

    # Pull out just the directive name (img-src, script-src, etc.).
    directive_name = report["violated-directive"].split(" ", 2).first

    # blocked-uri might be a full URL, just an origin, or just a scheme (like
    # "data"). Turn it into an origin or scheme.
    blocked_origin_or_scheme =
      if report["blocked-uri"].include?(":")
        # Looks like a URL or origin.
        Addressable::URI.parse(report["blocked-uri"]).origin
      else
        # Probably just a scheme.
        report["blocked-uri"]
      end

    rollup = [
      Api::SecurityViolation,
      directive_name,
      blocked_origin_or_scheme,
      document_host,
      parsed_useragent.name,
    ].join("")

    controller, action = begin
      Rails.application.routes.recognize_path(report["document-uri"]).values_at(:controller, :action)
    rescue ActionController::RoutingError
      %w[unknown unknown]
    end

    error = Api::SecurityViolation.new({
      "message" => "[%s] Directive \"%s\" blocked \"%s\"" % [document_host, directive_name, blocked_origin_or_scheme],
    })

    context = {
      app: case policy_enforcement_level
           when "report"  then "github-csp-report-only"
           when "enforce" then "github-csp"
           else                "github-csp-unknown"
           end,
      params: {},
      directive_name: directive_name,
      violated_directive: report["violated-directive"],
      browser: parsed_useragent.name,
      document_host: document_host,
      controller: controller,
      action: action,
      rollup: Digest::SHA256.hexdigest(rollup),
    }

    if directive_name == "require-trusted-types-for" && FeatureFlag.vexi.enabled?("trusted_types_stats", default: false)
      script_sample_sink = report["script-sample"].to_s.split("|", 2).first
      blocked_uri_type = trusted_types_blocked_uri_type(report["blocked-uri"])
      service_tag = %w[ui rails].include?(params[:service].to_s) ? params[:service].to_s : "rails"
      log_trusted_types_report(report, directive_name, document_host, controller, action, script_sample_sink, blocked_uri_type, service_tag)
      sink_name_tag = KNOWN_TRUSTED_TYPES_SINKS.include?(script_sample_sink) ? script_sample_sink : "other"
      disposition_tag = %w[report enforce].include?(policy_enforcement_level) ? policy_enforcement_level : "unknown"
      GitHub.dogstats.increment("browser_security_reports", tags: [
        "report_type:trusted_types",
        "browser:#{parsed_useragent.name}",
        "controller:#{controller}",
        "action:#{action}",
        "blocked_uri_type:#{blocked_uri_type}",
        "sink_name:#{sink_name_tag}",
        "disposition:#{disposition_tag}",
        "service:#{service_tag}",
      ])
    else
      Failbot.report!(error, context)
      GitHub.dogstats.increment("browser_security_reports", tags: ["report_type:csp", "browser:#{parsed_useragent.name}"])
    end
  rescue Addressable::URI::InvalidURIError
    # nbd, could be garbage
    GitHub.dogstats.increment("content_security_policy", tags: ["error:invalid_report"])
  end

  def log_trusted_types_report(report, directive_name, document_host, controller, action, script_sample_sink, blocked_uri_type, service_tag)
    GitHub.logger.warn("Trusted Types report", {
      "gh.trusted_types.directive_name": directive_name,
      "gh.trusted_types.violated_directive": report["violated-directive"],
      "gh.trusted_types.script_sample_sink": script_sample_sink,
      "gh.trusted_types.blocked_uri_type": blocked_uri_type,
      "gh.trusted_types.source_file": report["source-file"],
      "gh.trusted_types.line_number": report["line-number"],
      "gh.trusted_types.column_number": report["column-number"],
      "rails.controller.name": controller,
      "rails.controller.action": action,
      "url.host": document_host,
      "user_agent.name": parsed_useragent.name,
      "gh.exception.rollup": Digest::SHA256.hexdigest([directive_name, report["blocked-uri"], report["document-uri"], parsed_useragent.name].join("")),
      "gh.service": service_tag,
    })
  end

  def trusted_types_blocked_uri_type(blocked_uri)
    blocked_uri.to_s.start_with?("trusted-types-policy") ? "policy" : "sink"
  end

  # Attempt to detect reports from extensions and other unwanted sources.
  #
  # Returns true if we think the report comes from a plugin.
  def csp_report_noise?(report)
    source_file = report["source-file"]
    blocked_uri = report["blocked-uri"]
    script_sample = report["script-sample"]
    source_file.try(:start_with?, "chrome-extension://") ||
      blocked_uri.try(:start_with?, "safari-extension://") ||
      source_file.try(:start_with?, "safari-extension://") ||
      script_sample.try(:include?, "lastpass_iter")
  end

  # Override this method from Api::App to not require authentication on garage.
  def protect_access_to_garage_hosts
    # noop
  end

  # Override this method from Api::App to not require authentication on enterprise.
  def protect_access_to_enterprise_hosts
    # noop
  end

  # Disable browser caching for this API.
  def disable_caching!
    cache_control "no-cache"
  end

  def target_from_data(data)
    if GitHubUI::TARGETS.values.include?(data["target"])
      data["target"]
    else
      "full"
    end
  end

  def attachment_upload_error?(error)
    return false unless error.is_a?(Hash)

    error_payload = error["error"] || error[:error]
    return false unless error_payload.is_a?(Hash)

    (error_payload["type"] || error_payload[:type]) == "AttachmentUploadError"
  end
end
