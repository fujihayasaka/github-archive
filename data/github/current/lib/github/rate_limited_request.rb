# typed: true
# frozen_string_literal: true

# An ActionController mixin for rate-limiting controller actions.
#
# Class FooController < ApplicationController
#   include GitHub::RateLimitedRequest
#
#   rate_limit_requests \
#     :only     => :show,            # list of actions to limit (default all).
#     :except   => :index,           # list of actions to exclude from rate limiting.
#     :max      => 10,               # Integer or method symbol to call for max # of tries.
#     :key      => :generate_key,    # String or method symbol to call for rate limiter key.
#     :log_key  => :log_key,         # String or method symbol to call for key to use in logging.
#     :if       => :limit_filter,    # Method symbol for optional filter to disable limiting.
#     :ttl      => 1.hour,           # TTL of rate limit key in seconds.
#     :stealthy => true,             # Whether to check the rate limiter without incrementing the count.
#     :at_limit => :custom_response  # Method symbol for custom action when rate limit is hit;
#                                    # if this method performs rendering the default 429 status
#                                    # will not be returned.
#     :render_allow_body => true     # Whether to allow the GitHub::Limiters::Renderer middleware to
#                                    # respond with the rendered body (or replace it otherwise).
#                                    # Defaults to false, replacing the body (ignoring rendered content).
# end
module GitHub::RateLimitedRequest
  extend ActiveSupport::Concern
  include GitHub::RateLimitable

  extend T::Helpers
  requires_ancestor { ApplicationController }

  DEFAULT_RATE_LIMIT_TTL = 1.hour.to_i
  DEFAULT_RATE_LIMIT_MAX = 1000
  LEGACY_DEFAULT_RATE_LIMIT_TTL = 1.minute.to_i

  class ConfigurationError < StandardError; end

  OptionSet = ::Data.define(:if, :key, :log_key, :max, :ttl, :stealthy, :at_limit, :render_allow_body, :glb, :declaration_class) do
    T.bind(self, Class)

    def initialize(*args)
      initial_values = args[0] || {}
      [:if, :key, :log_key, :max, :ttl, :stealthy, :at_limit, :render_allow_body, :glb, :declaration_class].each do |key|
        initial_values[key] = nil unless initial_values.key?(key)
      end
      args[0] = initial_values
      super
    end
  end

  ControllerRateLimitOptions = Data.define(:default, :only, :except) do
    T.bind(self, Class)

    def initialize(*args)
      initial_values = args[0] || {}
      initial_values[:default] = OptionSet.new unless initial_values.key?(:default)
      initial_values[:only] = Hash.new(OptionSet.new) unless initial_values.key?(:only)
      initial_values[:except] = [] unless initial_values.key?(:except)
      args[0] = initial_values
      super
    end

    def default_values
      T.cast(self.class, Class).new
    end
  end

  included do
    T.bind(self, Class)
    class_attribute :rate_limit_options, default: ControllerRateLimitOptions.new, instance_accessor: false
  end

  module ClassMethods
    extend T::Helpers
    requires_ancestor { T.class_of(ApplicationController) }

    # Define rate limiting options in the controller class.
    def rate_limit_requests(options = {})
      # This is an append and not simply a before_action because the rate_limit_request DSL could have been called by
      # parent controllers, and we want to defer the actual rate limiting to after the rest of the class (and any
      # methods that might provide values for rate limit configuration keys) has been defined.
      append_before_action :check_rate_limit

      current_options = options.except(:only, :except)
      current_options[:declaration_class] = self.name

      option_properties = rate_limit_options.to_h.deep_dup
      defaults = option_properties[:default].to_h

      if options.key?(:only)
        [options[:only]].flatten.each do |action|
          option_properties[:only][action.to_sym] = OptionSet.new(**current_options)
        end
      else
        if options.key?(:except)
          option_properties[:except] += [options[:except]].flatten
        end

        # Defaults will be inherited from any parent controller's rate limit config, and "flattened" such that there
        # is only one set of defaults at this current controller.
        defaults = current_options.reverse_merge!(defaults)
      end

      # re-declaring rate_limit_requests with no :if and no :only/:except constraints implies removal of any :if filters
      if !options.key?(:only) && !options.key?(:except) && !options.key?(:if)
        defaults[:if] = nil
      end

      defaults[:render_allow_body] ||= false
      defaults[:glb] ||= false
      option_properties[:default] = OptionSet.new(**defaults)

      self.rate_limit_options = ControllerRateLimitOptions.new(**option_properties)
    end

    def rate_limit_options_for(action)
      return rate_limit_options.default unless rate_limit_options.only.key?(action.to_sym)

      action_options = rate_limit_options.only[action.to_sym]
      # default :if filters do not propagate to actions that have specific :only configuration
      default_options = rate_limit_options.default.with(if: nil)
      default_options.with(**action_options.to_h.compact)
    end
  end

  mixes_in_class_methods(ClassMethods)

  private

  def rate_limit_options
    @rate_limit_options ||= T.cast(self.class, ClassMethods).rate_limit_options_for(action_name.to_sym)
  end

  # Private: whether the current action should be rate-limited. All actions will be
  # rate limited unless explicitly excluded.
  def rate_limit_action?(action)
    T.cast(self.class, ClassMethods).rate_limit_options.except.exclude?(action.to_sym)
  end

  # Private: the method Symbol of the filter to selectively disable rate-limiting (default nil.)
  def rate_limit_filter
    @rate_limit_filter ||= rate_limit_options.if
  end

  # Private: the String rate limit key used to check whether this RateLimiter is at_limit?
  #
  # If a key was defined as a method Symbol, the controller method will be called to get the
  # value to use.
  #
  # If a key was defined as a String, it will be used.
  def rate_limit_key
    @rate_limit_key ||= begin
      key = rate_limit_options.key
      key = send(key) if key.is_a?(Symbol)
      raise ConfigurationError, "No rate limit key defined for #{self.class}##{action_name}" unless key
      key
    end
  end

  # Private: the String key used to log rate limited requests to Splunk
  #
  # If a key was defined as a method Symbol, the controller method will be called to get the
  # value to use.
  #
  # If a key was defined as a String, it will be used.
  #
  # If no key was defined, one will be generated by concatenating the parameterized
  # controller class name and action name.
  def rate_limit_log_key
    @rate_limit_log_key ||= begin
      key = rate_limit_options.log_key
      if key.nil?
        "#{self.class.to_s.parameterize.gsub('controller', '')}-#{action_name.parameterize}-count"
      elsif key.is_a?(Symbol)
        send(key)
      else
        key
      end
    end
  end

  # Private: the String key used to log rate limited requests to Datadog
  #
  # To prevent increasing the cardinality of tags in Datadog, we don't allow methods which might interpolate IDs (like
  # `rate_limit_log_key` allows) in our dogstats tags. Instead we always create a key based on the class and (if
  # available) the action name.
  def rate_limit_dogstats_key
    "#{self.class.to_s.parameterize.gsub('controller', '')}-#{action_name.parameterize}-count"
  end

  # Private: the Integer maximum number of requests to allow in the rate-limiter TTL.
  #
  # If a max was defined as a method Symbol, the controller method will be called to get
  # the value to use.
  #
  # If a max value was defined as an Integer, it will be used.
  #
  # If no max value was defined, returns nil.
  def rate_limit_max
    @rate_limit_max ||= begin
      max = rate_limit_options.max
      max_value = max.is_a?(Symbol) ? send(max) : max
      raise ConfigurationError, "No rate limit max defined for #{self.class}##{action_name}" unless max_value
      max_value
    end
  end

  # Private: the Integer TTL in seconds to track requests for the rate-limiter.
  #
  # If a ttl was defined as a method Symbol, the controller method will be called to get
  # the value to use.
  #
  # If a ttl value was defined as an Integer, it will be used.
  def rate_limit_ttl
    @rate_limit_ttl ||= begin
      ttl = rate_limit_options.ttl
      ttl_value = if ttl.is_a?(Symbol)
        send(ttl)
      else
        ttl
      end
      raise ConfigurationError, "No rate limit ttl defined for #{self.class}##{action_name}" unless ttl_value
      ttl_value
    end
  end

  def rate_limit_glb
    glb = rate_limit_options.glb
    @rate_limit_glb = glb.is_a?(Symbol) ? send(glb) : glb
    @rate_limit_glb
  end

  # Private: whether to suppress incrementing of the request count when checking
  # whether the rate limit has been reached.
  #
  # Returns Boolean.
  def rate_limit_stealthy(option_overrides = {})
    return rate_limit_options.stealthy if option_overrides[:stealthy].nil?

    option_overrides[:stealthy]
  end

  # Private: check whether this request should be rate-limited.
  #
  # If rate-limiting is enabled for the current controller action, and a rate-limiter
  # max is defined, and there is no defined filter that disables rate-limiting, checks
  # with the rate limiter to determine whether the limit has been reached.
  #
  # Returns Boolean.
  def at_rate_limit?(option_overrides = {})
    return false unless rate_limit_action?(option_overrides[:action] || action_name)
    return false if rate_limit_filter && send(rate_limit_filter) == false
    return true if (Rails.env.development? || Rails.env.test?) && params[:fakestate] == "ratelimited"

    rate_limit_options = {
      max_tries: rate_limit_max,
      ttl: rate_limit_ttl,
    }

    rate_limit_options
      .merge!(option_overrides)
      .delete(:action) # this isn't required by the limiter

    if rate_limit_stealthy(option_overrides)
      rate_limit_check_limited?(rate_limit_key, rate_limit_options)
    else
      rate_limit_increment_limited?(rate_limit_key, rate_limit_options)
    end
  end

  # Private: result of checking rate limit without incrementing.
  # Facilitates test mocks so that changes in RateLimitable do not affect RateLimitedRequest controller tests.
  def rate_limit_check_limited?(key, options = {})
    rate_limit_check(key, options).at_limit?
  end

  # Private: result of incrementing rate limit.
  # Facilitates test mocks so that changes in RateLimitable do not affect RateLimitedRequest controller tests.
  def rate_limit_increment_limited?(key, options = {})
    rate_limit_increment(key, options).at_limit?
  end

  # Private: check the rate limit and return a 429 "Too Many Requests" status/message
  # if limiting is enabled and the rate limit has been reached.
  #
  # If a method Symbol has been defined to record when the rate limit has been reached,
  # call the appropriate controller method when that happens.
  def check_rate_limit(option_overrides = {})
    render_rate_limited if GitHub.rate_limiting_enabled? && at_rate_limit?(option_overrides)
  end

  # Private: render a rate-limited response and status code.
  def render_rate_limited
    begin
      # Log to splunk as a limited request
      if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
        log_data["limited"] = "app/#{rate_limit_log_key}"
        log_data["apply_glb_rate_limit"] = rate_limit_glb
      end

      GitHub.dogstats.increment(
        "request_rate_limited",
        tags: ["limited:app/#{rate_limit_dogstats_key}", "apply_glb_rate_limit:#{rate_limit_glb}"]
      )

      GitHub.logger.info(
        "Request rate limited",
        controller_rate_limited: true,
        controller: self.class.name,
        action: action_name,
        user_id: current_user&.id,
        user: current_user&.name,
        log_key: rate_limit_log_key,
        # support for otel
        "gh.enduser.login": current_user&.name,
        "gh.enduser.id": current_user&.id
      )
      send(rate_limit_options.at_limit) if rate_limit_options.at_limit
    ensure
      env["limiter.renderer.allow_body"] = rate_limit_options.render_allow_body
      response.headers["X-GLB-Rate-Limit"] = "true" if rate_limit_glb

      unless performed?
        respond_to do |wants|
          wants.html_fragment do
            render \
              body: html_fragment_message,
              formats: :html,
              status: 429
          end

          wants.any do
            render \
              file: html_filename,
              layout: false,
              formats: :html,
              status: 429
          end
        end
      end
    end
  end

  def html_filename
    filename = if GitHub.enterprise?
      "/public/429-enterprise.html"
    else
      "/public/429.html"
    end

    "#{Rails.root}#{filename}"
  end

  def html_fragment_message
    "You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
  end
end
