# typed: false
# frozen_string_literal: true

# Rate limiting filters and requests helpers.

module Api::App::RateLimitDependency
  extend ActiveSupport::Concern

  class_methods do
    def skipped_rate_limit_paths
      @skipped_rate_limit_paths ||= Set.new
    end

    def rate_limit_as(family)
      # Provides the RateLimitConfiguration describing the rate limit rules for the
      # resource family associated with the current request and the API consumer
      # that initiated the request.
      define_method :rate_limit_configuration do
        GitHub.tracer.in_span("api.app-before", kind: :internal, attributes: {
          "code.namespace" => "rate_limit_configuration"
        }) do |_span|
          if defined?(@rate_limit_configuration)
            @rate_limit_configuration
          else
            @rate_limit_configuration = if family.nil?
              nil
            else
              GitHub.dogstats.distribution_time("api.rate_limit_configuration.duration", tags: ["family:#{family}"]) do
                Api::RateLimitConfiguration.for(
                  family,
                  self,
                )
              end
            end
          end
        end
      end
    end

    def early_limited_routes
      ["/search/code"]
    end
  end

  included do
    # Set the default configuration family
    # Concrete classes will likely want to set their own.
    rate_limit_as Api::RateLimitConfiguration::DEFAULT_FAMILY
  end

  # Determines whether access to the current route is forbidden once the
  # requestor uses up its rate limit.
  #
  # Returns a Boolean: true if access is forbidden once the rate limit is used
  # up; false otherwise.
  def rate_limited_route?
    !Api::App.skipped_rate_limit_paths.include?(route_pattern)
  end

  # This method is called twice during the life of a normal request:
  # - once in a `before` block, via `ensure_request_is_within_rate_limit!`
  # - once in an `after` block, via `increment_limit_and_set_headers!`
  def set_rate_limit!(rate)
    @rate = rate
    # We have to do this in two places because this mixin may be used with a JSONP
    # request which needs these headers to be serialized into the JSON response.
    rate.set_headers(@meta)
    rate.set_headers(response.headers)
  end

  # This method is called to modify the amount (cost) that is deducted from the currently authenticated
  # users rate limit balance. The amount is normally 1. There is no need to change it for the
  # vast majority of requests. Changing the amount will create a new throttler instance using
  # the current rate_limit_configuration. The change only affects the current api request and it will
  # default back to normal (amount=1) for subsequent requests.
  # Note: This has to be called before the Api::App::increment_rate_limit_and_set_headers! method for
  # it to take effect.
  def update_rate_limit_amount(amount)
    @rate_limit_amount = amount
    unless rate_limit_configuration.nil?
      options = { amount: increment_rate_limit_amount }
      @throttler = Api::ConfigThrottler.new(rate_limit_configuration, options)
    end
  end

  def increment_rate_limit_amount
    return @rate_limit_amount if defined?(@rate_limit_amount)
    @rate_limit_amount = 1
  end

  # @param code [Integer] JSONP always returns 200, allow it to pass a code here from a behavior standpoint.
  def increment_rate_limit_and_set_headers!(status_code: response.status.to_i)
    track_execution_time("post") do
      return if !rate_limiting_enabled?
      return if throttler.nil?
      return if @already_set_final_rate_limit_headers

      if use_early_limiter?
        if status_code == 304
          # Oops -- we deducted 1, but it turned out to be cached enough. Refund that.
          set_rate_limit!(throttler.credit!)
        else
          # sometimes, a `halt` will cause sinatra to start exiting before
          # `ensure_request_is_within_rate_limit!` was called.
          # In that case, apply `.rate!` here.
          check = @initial_rate_limit_check || (rate_limited_route? ? throttler.rate! : throttler.check)
          set_rate_limit!(check)
        end
      elsif status_code == 304 || !rate_limited_route?
        set_rate_limit!(throttler.check)
      else
        GitHub.dogstats.increment("api_rate_limiter.rate", tags: ["store:redis"], sample_rate: 0.01)
        set_rate_limit!(throttler.rate!)
      end
      @already_set_final_rate_limit_headers = true
    end
  end

  def use_early_limiter?
    if defined?(@use_early_limiter)
      @use_early_limiter
    else
      @use_early_limiter = self.class.early_limited_routes.include?(env["PATH_INFO"])
    end
  end

  def ensure_request_is_within_rate_limit!
    track_execution_time("pre") do |span|
      # We check the throttler first so that it is instantiated now to avoid it
      # possibly being inconsistent if rate limiting is disabled. See
      # https://github.com/github/github/pull/199767#issuecomment-976487737 and
      # following discussion.
      return if throttler.nil? || !rate_limited_route? || !rate_limiting_enabled?

      # If the request is over the limit,
      # this rate limiter response will be used to set headers
      # when returning early from the request.
      @initial_rate_limit_check = if use_early_limiter?
        GitHub.dogstats.increment("api_rate_limiter.check_and_rate", tags: ["store:redis"], sample_rate: 0.01)
        throttler.check_and_rate!
      else
        GitHub.dogstats.increment("api_rate_limiter.check", tags: ["store:redis"], sample_rate: 0.01)
        throttler.check
      end

      at_limit = @initial_rate_limit_check.at_limit?

      span.set_attribute("gh.api.rate_limiting.at_limit", at_limit) if span.present?

      if at_limit
        # Record the rate limited request
        auth_or_anon = rate_limit_configuration.authenticated_request? ? "auth" : "anon"
        family = rate_limit_configuration.family
        GitHub.dogstats.increment("rate_limited", { tags: ["via:api", "family:#{family}", "logged_in:#{auth_or_anon}", "store:redis"] })

        # Since we're returning early, set the headers now
        @already_set_final_rate_limit_headers = true
        set_rate_limit!(@initial_rate_limit_check)

        # Return an error response with a message
        type, id = rate_limit_configuration.key.split("-")
        message = if id
          "API rate limit exceeded for #{type} ID #{id}."
        else
          "API rate limit exceeded for #{type}."
        end

        if !rate_limit_configuration.authenticated_request?
          message += " (But here's the good news: " \
            "Authenticated requests get a higher rate limit. " \
            "Check out the documentation for more details.)"
        end

        # Include request_id in body to make it easier for customers to
        # find and include this info when reaching out to GitHub for help
        message += Api::ErrorHelper.rate_limit_message_for_request_id(GitHub.context[:request_id])

        deliver_error! rate_limit_status_code,
          message: message,
          documentation_url: "/rest/overview/rate-limits-for-the-rest-api"
      end
    end
  end

  def rate_limit_status_code
    403
  end

  # Internal: Provide an Api::ConfigThrottler for the current request.
  #
  # Returns an Api::Throttler.
  def throttler
    return @throttler if defined?(@throttler)
    return if rate_limit_configuration.nil?
    options = { amount: increment_rate_limit_amount }
    @throttler = Api::ConfigThrottler.new(rate_limit_configuration, options)
  end

  def rate_limiting_enabled?
    # Don't track rate limits for varnished requests. This is handled
    # at the Varnish layer already.
    return false if GitHub.varnish_enabled? && varnished?
    GitHub.rate_limiting_enabled?
  end

  def track_execution_time(position, &block)
    # avoiding interpolation here to not create new strings on each call
    span_name = "api.app-after"
    code_namespace = "ensure_request_is_within_rate_limit!-post"
    metric_name = "limiters.primary.executed.post"

    if position == "pre"
      span_name = "api.app-before"
      code_namespace = "ensure_request_is_within_rate_limit!-pre"
      metric_name = "limiters.primary.executed.pre"
    end

    GitHub.tracer.in_span(span_name, kind: :internal, attributes: { "code.namespace" => code_namespace }) do |span|
      GitHub.dogstats.distribution_time(metric_name) do
        block.call(span)
      end
    end
  end
end
