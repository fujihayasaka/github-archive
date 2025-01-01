# typed: strict
# frozen_string_literal: true

require "github/autonomous_system_actor"

module ApplicationController::ConcurrentRequestLimiterDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  # This filter adds the ability to enable a max concurrent request limit across web unicorns for a
  # given controller/action pair.

  # To enable: add the controller/action as an actor to the concurrent_web_requests_limited feature flag.
  # Enter this in devportal as a Flipper ID, e.g. GitHub::ControllerRouteActor:repository_imports_large_files-index
  # Namespaces in the controller name are separated by _ while the controller and action are separated by a -

  # Setting a TTL for this concurrency counter helps us to recover from drifts in accuracy of the counter
  # stemming from failed decrements by resetting the counter every 3 minutes. Consequently we also then allow
  # for a burst of up to double the expected concurrency for one request cycle after the TTL expires.
  CONCURRENT_WEB_REQUEST_TTL = 180 # seconds

  sig { params(request: T.untyped).returns(Symbol) }
  def concurrent_rate_limit_max_feature_flag(request)
    # Extract controller and action names from the request
    controller_name = request.params[:controller].gsub("/", "_")
    action_name = request.params[:action]

    # Construct and return feature flag name
    "dotcom_concurrency_limiter_#{controller_name}_#{action_name}_max".to_sym
  end

  sig { params(block: T.proc.void).void }
  def limit_concurrent_requests(&block)
    concurrency_incremented = false
    if limit_concurrent_requests?

      rate_limit_max = concurrent_rate_limit_max
      result = rate_limit_increment_without_overage(concurrent_rate_limit_key, { max_tries: rate_limit_max, ttl: CONCURRENT_WEB_REQUEST_TTL })
      if result.at_limit? && !result.incremented # reaching the limit during increment is allowable
        if FeatureFlag.vexi.enabled_or_raise?(:concurrent_web_requests_limited_dry) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          log_dry_run_limit_hit(rate_limit_max)
          yield
        else
          render_service_unavailable(rate_limit_max)
        end
      else
        concurrency_incremented = true
        yield # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    else
      yield
    end
  ensure
    begin
      if concurrency_incremented
        rate_limit_credit(concurrent_rate_limit_key, { ttl: 180 })
      end
    rescue => error
      Failbot.report(error)
    end
  end

  private

  sig { returns(String) }
  def concurrent_rate_limit_key
    "#{params[:controller]}:#{params[:action]}"
  end

  sig { returns(Numeric) }
  def concurrent_rate_limit_max
    actor_percent = FeatureFlag.vexi.percentage_of_actors_value_or_raise(concurrent_rate_limit_max_feature_flag(request)) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    actor_percent = actor_percent.zero? ? FeatureFlag.vexi.percentage_of_actors_value_or_raise(:concurrent_web_requests_limited_max) : actor_percent # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    actor_percent = actor_percent.zero? ? 100 : actor_percent
    (actor_percent * 100).to_i
  end

  sig { returns(T::Boolean) }
  def limit_concurrent_requests?
    limit_route? && limit_request?
  end

  sig { returns(T::Boolean) }
  def limit_route?
    route_feature_flag_actor.feature_flag_enabled?(:concurrent_web_requests_limited_route, default: false)
  end

  sig { returns(T::Boolean) }
  def limit_request?
    return false unless GitHub::AutonomousSystemActor.for(request).feature_flag_enabled?(:concurrent_web_requests_limited_as, default: false)

    if logged_in?
      route_feature_flag_actor.feature_flag_enabled?(:concurrent_web_requests_limited_authenticated, default: false)
    else
      true
    end
  end


  sig { params(key: String, options: T::Hash[Symbol, T.untyped]).returns(RedisRateLimiter::Result) }
  def rate_limit_increment_without_overage(key, options = {})
    limiter = RedisRateLimiter.new(key, options)
    result = limiter.rate_without_overage
    increment_rate_limit_hit if result.at_limit?
    result
  end

  sig { params(key: String, options: T::Hash[Symbol, T.untyped]).returns(RedisRateLimiter::Result) }
  def rate_limit_credit(key, options = {})
    limiter = RedisRateLimiter.new(key, options)
    result = limiter.credit
    result
  end

  sig { params(rate_limit_max: Numeric).void }
  def log_dry_run_limit_hit(rate_limit_max)
    GitHub.dogstats.increment(
      "concurrent_request_limited",
      tags: [
        "limited:#{concurrent_rate_limit_key}",
        "rate_limit_max:#{rate_limit_max}",
        "request_category:#{request_category}",
        "logged_in:#{logged_in?}",
        "dry_mode:true",
      ] + GitHub.context[:remote_call_source_datadog_tags]
    )
  end

  sig { params(rate_limit_max: Numeric).void }
  def render_service_unavailable(rate_limit_max)
    begin
      # Log to splunk as a limited request
      if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
        log_data["limited"] = "app/#{rate_limit_log_key}"
      end

      GitHub.dogstats.increment(
        "concurrent_request_limited",
        tags: [
          "limited:#{concurrent_rate_limit_key}",
          "rate_limit_max:#{rate_limit_max}",
          "request_category:#{request_category}",
          "logged_in:#{logged_in?}",
          "dry_mode:false",
        ] + GitHub.context[:remote_call_source_datadog_tags]
      )

      GitHub.logger.info(
        "Request concurrency rate limited",
        controller_rate_limited: true,
        controller: self.class.name,
        action: action_name,
        log_key: rate_limit_log_key,
      )
    ensure
      env["limiter.renderer.allow_body"] = rate_limit_options.render_allow_body

      unless performed?
        respond_to do |wants|
          wants.html_fragment do
            render \
              body: "The server is unavailable at this time. Please wait a few minutes before you try again.",
              formats: :html,
              status: 503
          end

          wants.any do
            render \
              file: service_unavailable_file_name,
              layout: false,
              formats: :html,
              status: 503
          end
        end
      end
    end
  end

  sig { returns(String) }
  def service_unavailable_file_name
    "#{Rails.root}/public/503.html"
  end
end
