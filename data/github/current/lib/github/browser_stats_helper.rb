# typed: true
# frozen_string_literal: true

require "addressable/uri"
require "codeowners"
require "net/http"
require "uri"

module GitHub
  module BrowserStatsHelper
    extend T::Helpers

    extend self

    TEN_MEGABYTES_IN_BYTES = 10_000_000
    IMAGE_TYPE = "image"
    VIDEO_TYPE = "video"
    OTHER_TYPE = "other"

    PJAX_FAILURE_REASONS = %w[response_error version_mismatch missing_response_body no_container]
    TURBO_FAILURE_REASONS = %w[request_failed turbo_disabled turbo_visit_control_is_reload tracked_element_mismatch].freeze
    BUNDLERS = %w[webpack webpack-next webpack-react-next]
    VALID_CONN_TYPES = ["slow-2g", "2g", "3g", "4g", "N/A"]
    BROWSER_CPU_BUCKETS = %w[unknown sm md lg xlg]

    RESOURCE_NAVIGATION_TIMINGS_REQUIRED_FIELDS = %w[name entry_type start_time duration]
    SOFT_NAV_REQUIRED_FIELDS = %w[destination duration initiator mechanism]
    WEB_VITALS_REQUIRED_FIELDS = %w[name]
    LONG_TASK_REQUIRED_FIELDS = %w[url duration name]
    LONG_ANIMATION_FRAME_REQUIRED_FIELDS = %w[url duration blocking_duration name]
    UPLOAD_TIMING_REQUIRED_FIELDS = %w[duration success]
    REACT_RENDER_PERFORMANCE_REQUIRED_FIELDS = %w[phase component_id actual_duration base_duration commit_lag react_version is_data_router_enabled app_name]
    REACT_HYDRATION_PERFORMANCE_REQUIRED_FIELDS = %w[duration react_version app_name render_type]

    BROWSER_INCREMENT_KEYS = {
      "ACTIONS_COMPLETED_LOG_VIEWS_SUCCEED" => "browser.events.actions.completed_log_views.succeed",
      "ACTIONS_COMPLETED_LOG_VIEWS_FAIL" => "browser.events.actions.completed_log_views.fail",
      "ACTIONS_STREAMING_LOG_VIEWS_SUCCEED" => "browser.events.actions.streaming_log_views.succeed",
      "ACTIONS_STREAMING_LOG_VIEWS_FAIL" => "browser.events.actions.streaming_log_views.fail",
      "ANIMATED_IMAGE_PLAYER_RENDER" => "browser.events.animated_image_player.render",
      "ANIMATED_IMAGE_PLAYER_SETUP" => "browser.events.animated_image_player.setup",
      "ANIMATED_IMAGE_PLAYER_WRAPPED" => "browser.events.animated_image_player.wrapped",
      "GENERATED_COMMIT_MESSAGE_SUCCESS" => "browser.events.commit_message.generation.success",
      "GENERATED_COMMIT_MESSAGE_ERROR" => "browser.events.commit_message.generation.error",
      "GENERATED_COMMIT_MESSAGE_ACCEPTED" => "browser.events.commit_message.generation.accepted",
      "REF_SELECTOR_BOOTED_FROM_LOCALSTORAGE" => "browser.events.ref_selector.boot.from_localstorage",
      "REF_SELECTOR_BOOTED_FROM_HTTP_CACHE" => "browser.events.ref_selector.boot.from_http_cache",
      "REF_SELECTOR_BOOTED_FROM_UNCACHED_HTTP" => "browser.events.ref_selector.boot.from_uncached_http",
      "REF_SELECTOR_BOOT_FAILED" => "browser.events.ref_selector.boot.failed",
      "REF_SELECTOR_UNEXPECTED_RESPONSE" => "browser.events.ref_selector.boot.unexpected",
      "REF_SELECTOR_LOCALSTORAGE_OVERFLOWED" => "browser.events.ref_selector.localstorage_overflowed",
      "REF_SELECTOR_LOCALSTORAGE_GAVE_UP" => "browser.events.ref_selector.localstorage_gave_up",
      "INSIGHTS_QUERY_EXECUTE_SUCCESS" => "browser.events.insights.query_succeeded",
      "INSIGHTS_QUERY_EXECUTE_ERROR" => "browser.events.insights.query_failed",
      "INSIGHTS_QUERY_TOKEN_FETCH_ERROR" => "browser.events.insights.token_fetch_failed",
      "SAFE_STORAGE_VALUE_EXPIRED" => "browser.events.safe_storage.value_expired",
      "SAFE_STORAGE_VALUE_WITHIN_TTL" => "browser.events.safe_storage.value_within_ttl",
      "ACCESSIBILITY_VIOLATIONS" => "github.accessibility.violations",
      "REACT_HYDRATION_ERROR" => "github.react_hydration.errors",
      "GLOBAL_SSO_BANNER_DISPLAYED" => "browser.events.sso_banner.global",
      "LEGACY_SSO_BANNER_DISPLAYED" => "browser.events.sso_banner.legacy",
      "LEGACY_SSO_BANNER_DISPLAYED_WITH_GLOBAL_BANNER_ENABLED" => "browser.events.sso_banner.legacy.global_banner_enabled",
      "MATHML_RENDERED" => "browser.events.math.mathml_rendered",
      "MODELS_CHAT_REQUEST" => "browser.events.models.chat_request_sent",
      "MODELS_CHAT_REQUEST_ERROR" => "browser.events.models.chat_request_error",
      "MODELS_MESSAGE_EDIT" => "browser.events.models.message_edit",
      "MODELS_PLAYGROUND_FEEDBACK_BANNER_DISPLAYED" => "browser.events.models.playground.feedback_banner.displayed",
      "MODELS_PLAYGROUND_FEEDBACK_BANNER_BOOK_CALL_SELECTED" => "browser.events.models.playground.feedback_banner.book_call_selected",
      "MODELS_PLAYGROUND_FEEDBACK_BANNER_SHARE_FEEDBACK_SELECTED" => "browser.events.models.playground.feedback_banner.share_feedback_selected",
      "MODELS_PLAYGROUND_FEEDBACK_POPOVER_DISPLAYED" => "browser.events.models.playground.feedback_popover.displayed",
      "MODELS_PLAYGROUND_FEEDBACK_POPOVER_BOOK_CALL_SELECTED" => "browser.events.models.playground.feedback_popover.book_call_selected",
      "MODELS_PLAYGROUND_FEEDBACK_POPOVER_SHARE_FEEDBACK_SELECTED" => "browser.events.models.playground.feedback_popover.share_feedback_selected",
      "UPDATABLE_CONTENT_XHR_REQUEST_VISIBLE" => "browser.events.updatable_content_xhr_request.visible",
      "UPDATABLE_CONTENT_XHR_REQUEST_INVISIBLE" => "browser.events.updatable_content_xhr_request.invisible",
      "REACT_RENDER" => "browser.react.render",
      "FETCH_ERROR" => "browser.fetch.error",
    }

    BROWSER_DISTRIBUTION_KEYS = {
      "COMMAND_PALETTE_FIRST_OPEN" => "command_palette.browser.events.first_open_duration",
      "GENERATED_COMMIT_MESSAGE_LATENCY" => "browser.events.commit_message.generation_latency",
      "MATH_INLINE_RENDERED" => "github.html_pipeline.math_filter.inline_duration",
      "MATH_DISPLAY_RENDERED" => "github.html_pipeline.math_filter.display_duration",
      "AXE_SCAN" => "github.accessibility.axe_scan_duration",
      "REACT_NAV_DURATION" => "browser.react.nav_duration",
      "SECURITY_OVERVIEW_DASHBOARD_INITIAL_START_TIME" => "security_overview.browser.events.dashboard_initial_start_time",
      "SECURITY_OVERVIEW_DASHBOARD_INITIAL_ALERT_TRENDS_LOAD_TIME" => "security_overview.browser.events.dashboard_initial_alert_trends_load_time",
    }

    BROWSER_DISTRIBUTION_TAGS = {
      "REACT_NAV_HARD" => "react_nav_type:hard",
      "REACT_NAV_SOFT" => "react_nav_type:soft",
      "REACT_NAV_TURBO" => "react_nav_type:turbo",
      "NAV_TURBO" => "nav_type:turbo"
    }

    BROWSER_SOFT_NAVIGATION_MECHANISM = {
      "HARD" => "hard",
      "TURBO" => "turbo",
      "FRAME" => "turbo.frame",
      "REACT" => "react",
      "UI" => "ui",
    }

    def self.included(base)
      base.helper_method(*instance_methods) if base.respond_to?(:helper_method)
    end

    # Returns a Browser instance
    def parsed_useragent
      T.bind(self, T.any(ApplicationController, ApplicationComponent, Api::BrowserReporting))
      user_agent = request.env["HTTP_USER_AGENT"]&.slice(0, Browser.user_agent_size_limit - 1)
      @parsed_useragent ||= Browser.new(user_agent)
    end

    def user_agent_platform(parsed_useragent)
      [parsed_useragent.platform.name, parsed_useragent.platform.version].compact.join(" ")
    end

    # Extracts the major version number from a UA string (if any)
    #
    # Returns an integer version number or zero
    def user_agent_major_version_number(full_version)
      full_version.split(".").first.to_i
    end

    # Public determines if the request's referrer matches the current host.
    # This is used to filter out stats from non-prod hosts.
    def referred_by_prod?
      T.bind(self, T.any(ApplicationController, ApplicationComponent, Api::BrowserReporting))
      referrer = Addressable::URI.parse(request.referrer)
      referrer.try(:hostname) == GitHub.host_name
    rescue Addressable::URI::InvalidURIError
      false
    end

    def guess_url_params(url)
      @url_params_cache ||= {}
      return @url_params_cache[url] if @url_params_cache[url]

      parsed_url = Addressable::URI.parse(url).to_s
      return unless parsed_url.present?

      @url_params_cache[url] = T.unsafe(GitHub::Application).routes.recognize_path(parsed_url, method: :get)
    rescue ActionController::RoutingError, Addressable::URI::InvalidURIError
      nil
    end

    def guess_url_controller_action(url)
      if params = guess_url_params(url)
        controller = GitHub::TaggingHelper.formatted_controller(params[:controller])
        [controller, params[:action]]
      end
    end

    # The autocomplete="one-time-code" attribute is only supported by
    # Safari 12 and up at the moment.
    def supports_autocomplete_otp?
      parsed_useragent.safari? && user_agent_major_version_number(parsed_useragent.full_version) >= 12
    end

    def report_metrics(stats, user_agent:, ip:, snek: false)
      return unless user_agent
      parsed_useragent = Browser.new(user_agent)
      return if parsed_useragent.bot?

      if parsed_useragent.name
        parameterized_browser = EncodingSafeParameterizeHelper.encoding_safe_parameterize(parsed_useragent.name)
        user_agent_tag = "useragent:#{parameterized_browser}"
        mobile_tag = "mobile:#{!!parsed_useragent.device.mobile?}"
      end

      stats.each do |stat|
        tags = [user_agent_tag, mobile_tag, "logged_in:#{!!stat["logged_in"]}", "staff:#{!!stat["staff"]}", "snek:#{snek}"]
        tags << "bundler:#{stat["bundler"]}" if BUNDLERS.include?(stat["bundler"])

        if referred_request_url = stat["referred_request_url"]
          if match = guess_url_controller_action(referred_request_url.to_s)
            tags << "referred_controller:#{match[0]}"
            tags << "referred_action:#{match[1]}"
          end
        end

        if request_url = stat["request_url"]
          if match = guess_url_controller_action(request_url.to_s)
            tags << "controller:#{match[0]}"
            tags << "action:#{match[1]}"
          end
        end

        tags.freeze

        report_downloaded_bundles(Array.wrap(stat["downloaded_bundles"]), tags: tags) if stat["downloaded_bundles"]
        report_turbo_stats(stat, tags: tags)
        report_turbo_failure_reasons(stat, tags: tags)
        report_timings(Array.wrap(stat["resource_timings"]) + Array.wrap(stat["navigation_timings"]), tags: tags)
        report_web_vitals(Array.wrap(stat["web_vital_timings"]), tags: tags, ip: ip) if stat["web_vital_timings"]
        report_long_tasks(Array.wrap(stat["long_tasks"]), tags: tags)
        report_long_animation_frames(Array.wrap(stat["long_animation_frames"]), tags: tags)
        report_increment_key(stat, tags: tags)
        report_distribution_key(stat, tags: tags)
        report_hydro_event(stat)
        report_upload_timing(stat) if stat["upload_timing"]
        report_soft_navigation(stat, tags: tags)
        report_react_render_performance(stat["react_render_performance"], tags: tags)
        report_react_hydration_performance(stat["react_hydration_timings"], tags: tags) if stat["react_hydration_timings"]
      end
    end

    def report_metrics_json(input, user_agent:, ip:, snek: false)
      stats = input["stats"].map do |input_stat|
        stat = input_stat.try(:deep_transform_keys, &:underscore)

        stat["increment_key"] = BROWSER_INCREMENT_KEYS[stat["increment_key"]] if stat.has_key?("increment_key")
        stat["increment_tags"] = stat["increment_tags"].try(:transform_keys, &:underscore) if stat.has_key?("increment_tags")

        stat["distribution_key"] = BROWSER_DISTRIBUTION_KEYS[stat["distribution_key"]] if stat.has_key?("distribution_key")
        stat["distribution_tags"] = stat["distribution_tags"].map { |tag| BROWSER_DISTRIBUTION_TAGS[tag] } if stat.has_key?("distribution_tags")

        stat["resource_timings"] = parse_navigation_resource_timing(stat["resource_timings"]) if stat.has_key?("resource_timings")
        stat["navigation_timings"] = parse_navigation_resource_timing(stat["navigation_timings"]) if stat.has_key?("navigation_timings")

        stat["soft_navigation_timing"]["mechanism"] = BROWSER_SOFT_NAVIGATION_MECHANISM[stat["soft_navigation_timing"]["mechanism"].to_s] if stat.has_key?("soft_navigation_timing")

        stat["upload_timing"] = stat["upload_timing"].transform_keys(&:underscore) if stat.has_key?("upload_timing")
        stat["web_vital_timings"] = parse_web_vitals_timings(stat["web_vital_timings"]) if stat.has_key?("web_vital_timings")

        stat["long_animation_frames"] = stat["long_animation_frames"].map { |s| s.transform_keys(&:underscore) } if stat.has_key?("long_animation_frames")

        stat.compact
      end
      report_metrics(stats, user_agent: user_agent, ip: ip, snek: snek)
    rescue StandardError => error # rubocop:todo Lint/RescueException
      GitHub.logger.warn("Browser stats invalid stats", {
        "code.namespace": "GitHub::BrowserStatsHelper",
        "code.function": "report_metrics_json",
        "exception.message": error.full_message,
      })
    end

    def parse_web_vitals_timings(web_vitals_timings)
      web_vitals_timings.try(:map) do |timing|
        timing["mechanism"] = BROWSER_SOFT_NAVIGATION_MECHANISM[timing["mechanism"]]
        timing["network_conn_type"] = timing["network_conn_type"] || "N/A"

        timing["soft"] = !!timing["soft"]
        timing["ssr"] = !!timing["ssr"]
        timing["lazy"] = !!timing["lazy"]
        timing["alternate"] = !!timing["alternate"]
        timing["synthetic"] = !!timing["synthetic"]
        timing["hpc_found"] = !!timing["hpc_found"]
        timing["hpc_gql_fetched"] = !!timing["hpc_gql_fetched"]
        timing["hpc_js_fetched"] = !!timing["hpc_js_fetched"]
        timing["header_redesign"] = !!timing["header_redesign"]
        timing.compact
      end
    end

    def parse_navigation_resource_timing(navigation_or_resource_timings)
      navigation_or_resource_timings.try(:map) do |navigation_or_resource_timing|
        navigation_or_resource_timing["name"] = URI.parse(navigation_or_resource_timing["name"])
        navigation_or_resource_timing.transform_keys(&:underscore)
      end
    rescue URI::InvalidURIError
      nil
    end

    def report_upload_timing(stat)
      timing = stat["upload_timing"]
      return unless UPLOAD_TIMING_REQUIRED_FIELDS.all? { |field| timing.key?(field) }
      tags = [
        "success:#{timing["success"]}",
        "type:#{type(timing["file_type"])}",
      ]
      tags << "over_sized:#{over_sized?(timing["size"])}" if timing["size"]

      GitHub.dogstats.distribution(
        "browser.upload_performance",
        timing["duration"].to_i,
        tags: tags
      )
    end

    private def type(file_type)
      return IMAGE_TYPE if image?(file_type)
      return VIDEO_TYPE if video?(file_type)

      OTHER_TYPE
    end

    private def image?(file_type)
      ::Storage::Uploadable::IMAGE_CONTENT_TYPES.keys.include? file_type
    end

    private def video?(file_type)
      ::Storage::Uploadable::VIDEO_CONTENT_TYPES.keys.include? file_type
    end

    private def over_sized?(size)
      size > TEN_MEGABYTES_IN_BYTES
    end

    def report_downloaded_bundles(bundles, tags:)
      return unless bundles
      bundles = bundles.select do |bundle|
        valid_bundle?(bundle)
      end
      bundles.each do |bundle|
        GitHub.dogstats.increment("browser.bundle_downloads", tags: tags + ["bundle:#{bundle}"])
      end
    end

    def report_turbo_stats(stats, tags:)
      return unless stats["turbo_duration"]
      GitHub.dogstats.distribution("browser.turbo_performance", stats["turbo_duration"], tags: tags)
    end

    def report_web_vitals(timings, tags:, ip:)
      timings.each do |timing|
        return unless WEB_VITALS_REQUIRED_FIELDS.all? { |field| timing.has_key?(field) }

        if !is_app_name?(timing["app"])
          GitHub.dogstats.increment("browser.web_vitals.rejected", tags: ["reason:bad_app_name"])
          next
        end

        timing_tags = tags.dup

        if match = guess_url_controller_action(timing["name"].to_s)
          timing_tags << "controller:#{match[0]}"
          timing_tags << "action:#{match[1]}"

          localization_config = Localization::Config.new(request: Struct.new(:remote_ip).new(ip))
          timing_tags << "country:#{localization_config.country_code}" if localization_config.country_code
        end

        timing_tags << "app_name:#{timing["app"]}"
        timing_tags << "soft:#{timing["soft"]}"
        timing_tags << "ssr:#{timing["ssr"]}"
        timing_tags << "lazy:#{timing["lazy"].present?}"
        timing_tags << "synthetic:#{timing["synthetic"].present?}"
        timing_tags << "cpu:#{timing["cpu"]}" if BROWSER_CPU_BUCKETS.include?(timing["cpu"])

        timing_tags << "mechanism:#{timing["mechanism"]}" if timing["mechanism"].present?

        if FeatureFlag.vexi.enabled?(:sample_network_conn_type, default: false) && valid_conn_type?(timing["network_conn_type"])
          timing_tags << "network_conn_type:#{timing["network_conn_type"]}"
        end

        if timing["elementtiming"].present? && timing["identifier"].present?
          timing_tags << "identifier:#{timing["identifier"]}"
        end

        GitHub.dogstats.distribution("browser.vitals.dist.cls", timing["cls"], tags: timing_tags) unless timing["cls"].nil?
        GitHub.dogstats.distribution("browser.vitals.dist.fcp", timing["fcp"], tags: timing_tags) unless timing["fcp"].nil?
        GitHub.dogstats.distribution("browser.vitals.dist.fid", timing["fid"], tags: timing_tags) unless timing["fid"].nil?
        GitHub.dogstats.distribution("browser.vitals.dist.lcp", timing["lcp"], tags: timing_tags) unless timing["lcp"].nil?
        GitHub.dogstats.distribution("browser.vitals.dist.ttfb", timing["ttfb"], tags: timing_tags) unless timing["ttfb"].nil?
        GitHub.dogstats.distribution("browser.vitals.dist.elementtiming", timing["elementtiming"], tags: timing_tags) unless timing["elementtiming"].nil?

        if !timing["hpc"].nil?
          timing_tags << "found:#{timing["hpc_found"]}"
          timing_tags << "gql_fetched:#{timing["hpc_gql_fetched"]}"
          timing_tags << "js_fetched:#{timing["hpc_js_fetched"]}"
          timing_tags << "header_redesign:#{timing["header_redesign"]}"

          if timing["hpc"].to_i > 60_000
            GitHub.dogstats.increment("browser.web_vitals.rejected", tags: ["reason:high_hpc"])
          else
            GitHub.dogstats.distribution("browser.vitals.dist.hpc", timing["hpc"], tags: timing_tags)
          end
        end

        GitHub.dogstats.distribution("browser.vitals.dist.inp", timing["inp"], tags: timing_tags) unless timing["inp"].nil?
      end
    end

    def report_long_tasks(timings, tags:)
      timings.each do |timing|
        return unless LONG_TASK_REQUIRED_FIELDS.all? { |field| timing.has_key?(field) }
        timing_tags = tags.dup

        if match = guess_url_controller_action(timing["url"].to_s)
          timing_tags << "controller:#{match[0]}"
          timing_tags << "action:#{match[1]}"
        end

        timing_tags << "name:#{timing["name"]}"

        GitHub.dogstats.distribution("browser.long_task", timing["duration"], tags: timing_tags)
      end
    end

    def report_react_hydration_performance(hydration_stats, tags:)
      return unless hydration_stats
      return unless REACT_HYDRATION_PERFORMANCE_REQUIRED_FIELDS.all? { |field| hydration_stats.has_key?(field) }
      return unless hydration_stats["render_type"] == "hydrateRoot" || hydration_stats["render_type"] == "createRoot"

      tags = tags.dup
      tags << "app_name:#{hydration_stats["app_name"]}"
      tags << "react_version:#{hydration_stats["react_version"]}"
      tags << "render_type:#{hydration_stats["render_type"]}"
      GitHub.dogstats.distribution("browser.react.hydration.duration", hydration_stats["duration"], tags: tags)
    end

    def report_react_render_performance(render_stats, tags:)
      return unless render_stats
      return unless REACT_RENDER_PERFORMANCE_REQUIRED_FIELDS.all? { |field| render_stats.has_key?(field) }
      tags = tags.dup
      tags << "phase:#{render_stats["phase"]}"
      tags << "component_id:#{render_stats["component_id"]}"
      tags << "app_name:#{render_stats["app_name"]}"
      tags << "data_router:#{render_stats["is_data_router_enabled"]}"
      tags << "react_version:#{render_stats["react_version"]}"

      GitHub.dogstats.distribution("browser.react.profiler.actual_duration", render_stats["actual_duration"], tags: tags)
      GitHub.dogstats.distribution("browser.react.profiler.base_duration", render_stats["base_duration"], tags: tags)
      GitHub.dogstats.distribution("browser.react.profiler.commit_lag", render_stats["commit_lag"], tags: tags)
    end

    def report_long_animation_frames(timings, tags:)
      timings.each do |timing|
        return unless LONG_ANIMATION_FRAME_REQUIRED_FIELDS.all? { |field| timing.has_key?(field) }
        timing_tags = tags.dup

        if match = guess_url_controller_action(timing["url"].to_s)
          timing_tags << "controller:#{match[0]}"
          timing_tags << "action:#{match[1]}"
        end

        timing_tags << "name:#{timing["name"]}"

        GitHub.dogstats.distribution("browser.long_animation_frame.duration", timing["duration"], tags: timing_tags)
        GitHub.dogstats.distribution("browser.long_animation_frame.blocking_duration", timing["blocking_duration"], tags: timing_tags)
      end
    end

    def report_timings(timings, tags:)
      timings.each do |timing|
        return unless RESOURCE_NAVIGATION_TIMINGS_REQUIRED_FIELDS.all? { |field| timing.key?(field) }

        timing_tags = tags.dup

        # TODO: Restrict entryType via GraphQL Enum
        case timing["entry_type"]
        when "navigation", "resource"
          entry_type = timing["entry_type"]
        else
          next
        end

        # TODO: Restrict initiatorType via GraphQL Enum
        case timing["initiator_type"]
        when "navigation", "xmlhttprequest", "fetch", "beacon", "link", "script", "img"
          timing_tags << "initiator:#{timing["initiator_type"]}"
        else
          timing_tags << "initiator:other"
        end

        case timing["initiator_type"]
        when "navigation", "xmlhttprequest", "fetch", "beacon"
          if entry_type != "resource" && (match = guess_url_controller_action(timing["name"].to_s))
            timing_tags << "controller:#{match[0]}"
            timing_tags << "action:#{match[1]}"
          end
        when "link", "script", "img"
          path = timing["name"].path
          if path.try(:start_with?, "/assets")
            name = bare_bundle_name(path)
            if valid_bundle?(name)
              timing_tags << "bundle:#{name}"
            end
          end
        end

        dogstats = GitHub.dogstats
        dogstats.distribution("browser.#{entry_type}.dist.duration", timing["duration"], tags: timing_tags) if timing["duration"] > 0
        dogstats.distribution("browser.#{entry_type}.dist.transfersize", timing["transfer_size"], tags: timing_tags) if timing["transfer_size"].to_i > 0
        report_timing_range(dogstats, "browser.#{entry_type}.dist.processing", timing, "response_end", "load_event_start", tags: timing_tags)

        if entry_type == "navigation"
          dogstats.distribution("browser.#{entry_type}.dist.decodedbodysize", timing["decoded_body_size"], tags: timing_tags) if timing["decoded_body_size"].to_i > 0
          dogstats.distribution("browser.#{entry_type}.dist.encodedbodysize", timing["encoded_body_size"], tags: timing_tags) if timing["encoded_body_size"].to_i > 0
          report_timing_range(dogstats, "browser.#{entry_type}.dist.appcache", timing, "fetch_start", "domain_lookup_start", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.dns", timing, "domain_lookup_start", "domain_lookup_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.domcomplete", timing, "dom_content_loaded_event_end", "dom_complete", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.domcontentloaded", timing, "dom_content_loaded_event_start", "dom_content_loaded_event_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.dominteractive", timing, "response_end", "dom_interactive", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.onload", timing, "load_event_start", "load_event_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.redirect", timing, "redirect_start", "redirect_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.request", timing, "request_start", "response_start", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.response", timing, "response_start", "response_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.tcp", timing, "connect_start", "connect_end", tags: timing_tags)
          report_timing_range(dogstats, "browser.#{entry_type}.dist.unload", timing, "unload_event_start", "unload_event_end", tags: timing_tags)
        end
      end
    end

    def report_timing_range(dogstats, name, timing, startKey, endKey, tags:)
      return unless timing[startKey] && timing[endKey]
      ms = timing[endKey] - timing[startKey]
      return unless ms > 0
      return if ms > 1.year * 1000
      dogstats.distribution(name, ms, tags: tags)
    end

    def report_increment_key(stat, tags:)
      return unless stat["increment_key"]
      increment_tags = (stat["increment_tags"] || {}).map do |key, value|
        "#{key}:#{value}"
      end
      GitHub.dogstats.increment(stat["increment_key"], tags: tags + increment_tags)
    end

    def report_distribution_key(stat, tags:)
      return unless stat["distribution_key"] && stat["distribution_value"]
      distribution_tags = stat["distribution_tags"] || []
      GitHub.dogstats.distribution(stat["distribution_key"], stat["distribution_value"], tags: tags + distribution_tags)
    end

    def report_soft_navigation(stat, tags:)
      soft_nav = stat["soft_navigation_timing"]
      return unless soft_nav && SOFT_NAV_REQUIRED_FIELDS.all? { |field| soft_nav.has_key?(field) }
      return unless is_app_name?(soft_nav["initiator"]) && is_app_name?(soft_nav["destination"])

      GitHub.dogstats.distribution(
        "browser.soft_navigation.performance.ctr",
        soft_nav["duration"],
        tags: tags + [
          "mechanism:#{soft_nav["mechanism"]}",
          "initiator:#{soft_nav["initiator"]}",
          "destination:#{soft_nav["destination"]}"
        ]
      )
    end

    def report_turbo_failure_reasons(stat, tags:)
      return unless stat["turbo_failure_reason"]

      (reason, *mismatches) = stat["turbo_failure_reason"].split("-")

      return unless TURBO_FAILURE_REASONS.include?(reason)

      turbo_tags = tags + mismatches.map do |mismatch|
        "mismatch:#{mismatch}"
      end

      if match = guess_url_controller_action(stat["turbo_start_url"].to_s)
        turbo_tags << "start:#{match[0]}##{match[1]}"
      end

      if match = guess_url_controller_action(stat["turbo_end_url"].to_s)
        turbo_tags << "end:#{match[0]}##{match[1]}"
      end

      GitHub.dogstats.increment("browser.turbo_failure_reason.#{reason}", tags: turbo_tags)
    end

    def report_hydro_event(stat)
      return unless stat["hydro_event_payload"]

      decoded = HydroHelper.decode_hydro_payload(
        hmac: stat["hydro_event_hmac"],
        encoded: stat["hydro_event_payload"],
      )
      event_type = decoded[:event_type]
      payload = convert_to_hash(decoded[:payload])

      if stat["visitor_payload"] && stat["visitor_hmac"]
        visitor_payload = VarnishHelper.decode_visitor_payload(
          stat["visitor_payload"], stat["visitor_hmac"]
        )

        visitor_id = visitor_payload[:visitor_id].to_i
        if visitor_id > 0
          payload[:visitor_id] = visitor_id
          payload[:client_id] = Analytics::OctolyticsId.coerce(visitor_id).unversioned
        end

        payload.merge!(
          referrer: visitor_payload[:referrer],
          originating_request_id: visitor_payload[:request_id],
        )
      end

      hydro_dogstats_tags = ["hydro_event_type:#{event_type}"]
      hydro_dogstats_tags.push("feature:#{payload[:feature_slug]}") if payload.include?(:feature_slug)

      GitHub.dogstats.increment("hydro.browser_event", tags: hydro_dogstats_tags)

      GlobalInstrumenter.instrument("browser.#{event_type}", payload.merge({
        client: {
          user: User.find_by(id: payload[:user_id]),
          timestamp: stat["timestamp"] ? stat["timestamp"] / 1000 : nil,
          context: HydroHelper.decode_hydro_client_context(stat["hydro_client_context"]),
        },
      }))
    rescue HydroHelper::InvalidPayloadError => e
      GitHub.dogstats.increment("hydro.browser_event.invalid_payload")

      # HMAC failures will always happen in the thousands, and we don't need to report every one of those to Sentry.
      if Kernel.rand(100) == 0
        GitHub.report_hydro_error(e, hydro_dropped: {
          hmac: stat["hydro_event_hmac"],
          payload: stat["hydro_event_payload"]
        })
      end
    end

    def is_app_name?(name)
      name&.match?(/\A[\w|-]+\z/)
    end

    def valid_conn_type?(conn_type)
      VALID_CONN_TYPES.include?(conn_type)
    end

    sig { params(payload: Object).returns(T::Hash[Symbol, T.anything]) }
    private def convert_to_hash(payload)
      Kernel.Hash(payload)
    end

    def valid_bundle?(bundle)
      bundle.ends_with?(".js") || bundle.ends_with?(".css")
    end

    def bare_bundle_name(source)
      File.basename(source).sub(/\A([\w(\-|\.)]+)-[a-f0-9]+(\.\w+)\Z/, '\1\2')
    end
  end
end
