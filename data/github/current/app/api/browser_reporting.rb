# typed: true
# frozen_string_literal: true

class Api::BrowserReporting < Api::App

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

    if GitHub.flipper[:browser_stats_disabled].enabled?
      deliver_raw("", status: 200, content_type: "text/plain")
      return
    end

    begin
      data = receive(Hash, required: true)

      GitHub::BrowserStatsHelper.report_metrics_json(
        data,
        user_agent: GitHub.context[:user_agent],
        ip: GitHub.context[:real_ip]
      )
    rescue StandardError => error # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("browser.reporting_errors")

      GitHub.logger.warn("Browser stats error", {
        "code.namespace": "Api::BrowserReporting",
        "code.function": "stats",
        "exception.message": error.message
      })

      deliver_error!(400)
    end

    deliver_raw("", status: 200, content_type: "text/plain")
  end

  post "/_private/browser/errors", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/web-systems-reviewers"
    error = receive
    deliver_error!(400) unless error.is_a?(Hash)

    if error["csp-report"]
      policy_enforcement_level = request.params["csp_enforcement"] || "enforce"
      report_csp_error(error["csp-report"], policy_enforcement_level)
    else
      response = platform_execute(ErrorsQuery, variables: { input: error }, force_readonly: true)
      GitHub.dogstats.increment("browser.reporting_errors") if response.errors.all.any?
    end

    deliver_raw("", status: 200, content_type: "text/plain")
  end

  private

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

    report_bucket = if directive_name == "require-trusted-types-for"
      "github-trusted-types"
    else
      if policy_enforcement_level == "report-only"
        "github-csp-report-only"
      else
        "github-csp"
      end
    end

    controller, action = begin
      Rails.application.routes.recognize_path(report["document-uri"]).values_at(:controller, :action)
    rescue ActionController::RoutingError
      %w[unknown unknown]
    end

    error = Api::SecurityViolation.new({
      "message" => "[%s] Directive \"%s\" blocked \"%s\"" % [document_host, directive_name, blocked_origin_or_scheme],
    })

    context = {
      app: report_bucket,
      params: {},
      directive_name: directive_name,
      violated_directive: report["violated-directive"],
      browser: parsed_useragent.name,
      document_host: document_host,
      controller: controller,
      action: action,
      rollup: Digest::SHA256.hexdigest(rollup),
    }

    report_type = if directive_name == "require-trusted-types-for"
      "trusted_types"
    else
      "csp"
    end

    tags = ["report_type:#{report_type}", "browser:#{parsed_useragent.name}"]
    if report_type == "trusted_types"
      GitHub.logger.tagged("code.namespace": self.class.name, "code.function": __method__) do
        log_trusted_types_report context
      end
      tags += ["controller:#{context[:controller]}", "action:#{context[:action]}"]
    else
      Failbot.report!(error, context)
    end
    GitHub.dogstats.increment("browser_security_reports", tags: tags)
  rescue Addressable::URI::InvalidURIError
    # nbd, could be garbage
    GitHub.dogstats.increment("content_security_policy", tags: ["error:invalid_report"])
  end

  def log_trusted_types_report(context)
    GitHub.logger.warn("Trusted Types report", {
      "rails.controller.action": context[:action],
      "rails.controller.name": context[:controller],
      "gh.exception.project": context[:app],
      "gh.exception.rollup": context[:rollup],
      "gh.trusted_types.directive_name": context[:directive_name],
      "gh.trusted_types.violated_directive": context[:violated_directive],
      "url.host": context[:document_host],
      "user_agent.name": context[:browser],
    })
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
end
