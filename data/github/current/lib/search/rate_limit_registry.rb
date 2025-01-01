# typed: true
# frozen_string_literal: true

# This class provides a common framework for registering and triggering new
# controller-based rate limiters. It is designed with a few core principles in
# mind:
# - Rate limiters can be easily added and configured.
# - Rate limiter instances will be imutable for thread safety. Any rate
#   limiting event they handle should not change their state.
# - Not all rate limiters will limit - some may be passive for testing/tuning
# - Multiple rate limiters of the same class may be configured with different
#   options, for any reason
# - It's up to each rate limiter to decide how to track its limit, what the
#   units are, how and when they are incremented, who it applies to, and what
#   to do when the limit is reached.
# - Each limiter instance tracks its own state per request.
# - The finish callback is always called for cleanup, even on error. Rate limiters can ignore it or use it to increment or refund, and each limiter
#
# This can be used by both Rails controllers and Sinatra apps out of the box.
# Adding to other types of objects should be possible with a little extra setup
# - the host just needs to be able to callback to the `around`, or `start` and
# `finish` triggers.
#
# The only thing that makes this search-specific at the moment is the check for
# `search_rate_limiters_enabled?`, but this could easily be generalized to
# support other types of rate limiters by abstracting the enabled check.
module Search::RateLimitRegistry
  extend ActiveSupport::Concern
  include Kernel

  # A rudimentary state machine that tracks whether each rate limiter was run
  # and what the result was. A given limiter's state is passed in to the
  # `:finish_request` method along with the `:limiter` and can be used to
  # decide how to proceed with any post processing using predicate methods:
  #
  # initialized? - The default state; the limiter hasn't been run
  #   started?   - Processing has started (i.e. an earlier limiter wasn't
  #                `halted?`)
  #     skipped? - The request was skipped due to a `:only` or `:except` filter
  #     ok?      - The `:start_request` method was nil or returned `:OK`
  #     halted?  - The `:start_request` method returned something other than
  #                `:OK`; later limiters will not be run (i.e. will not be
  #                `started?`)
  # performed?   - The limiter ran; equivalent to `ok? || halted?`
  # finished?    - The limiter is finished processing; equivalent to
  #                `performed? || skipped?`
  class SearchRateLimitState
    class BadState < StandardError; end

    INITIALIZED = :INITIALIZED
    STARTING = :STARTING
    SKIPPED = :SKIPPED
    OK = :OK
    HALTED = :HALTED

    def initialize
      @state = INITIALIZED
    end

    def initialized?
      @state == INITIALIZED
    end

    def start!
      raise BadState unless initialized?
      @state = STARTING
    end

    def started?
      @state == STARTING
    end

    def skip!
      raise BadState unless started?
      @state = SKIPPED
    end

    def skipped?
      @state == SKIPPED
    end

    def ok!
      raise BadState unless started?
      @state = OK
    end

    def ok?
      @state == OK
    end

    def halt!
      raise BadState unless started?
      @state = HALTED
    end

    def halted?
      @state == HALTED
    end

    def performed?
      ok? || halted?
    end

    def finished?
      skipped? || performed?
    end
  end

  included do
    T.bind(self, Class)
    # This will automatically register the before and after filters for Rails
    # controllers and Sinatra apps. For use with other types of objects you'll
    # have to configure the callbacks manually.
    if self <= ActionController::Base
      # Using `around_action` for ActionControllers ensures that our
      # `:finish_request` methods will run even if a `:start_request` method
      # renders or redirects, which would otherwise prevent an `after_action`
      # from running.
      around_action :search_rate_limiters_around,
        if: :search_rate_limiters_enabled?
    elsif self <= Sinatra::Base
      # In Sinatra::Base, calling `halt` immediately interrupts the rest of the
      # `before` filter and the request, but `after` filters will still be
      # triggered.
      before do
        T.bind(self, Search::RateLimitRegistry)
        search_rate_limiters_start if search_rate_limiters_enabled?
      end

      after do
        T.bind(self, Search::RateLimitRegistry)
        search_rate_limiters_finish if search_rate_limiters_enabled?
      end
    end
  end

  class_methods do
    # Registers a new rate limiter for the class it is called from.
    #
    # There's no factory pattern for the rate limiter to conform to because
    # you'll customize how the rate is checked and incremented and what happens
    # when the limit is reached in the methods whose symbols you pass to
    # `:start_request` and `:finish_request`. These will be called automatically
    # via `search_rate_limiters_start` and `search_rate_limiters_finish`
    # respectively. You must ensure that your rate limiter instances are
    # immutable for threadsafety.
    def register_search_rate_limiter(limiter, options = {})
      search_rate_limiters[limiter] = {
        start_request: options.fetch(:start_request, nil),
        finish_request: options.fetch(:finish_request, nil),
        only: Kernel.Array(options.fetch(:only, [])),
        except: Kernel.Array(options.fetch(:except, [])),
        if: options.fetch(:if, nil),
        unless: options.fetch(:unless, nil)
      }.freeze # Make immutable
    end

    # Stores info about each registered rate limiter
    def search_rate_limiters
      @search_rate_limiters ||= {}
    end
  end

  protected

  def render_search_rate_limiter_halt!(limiter_name)
    # In production, `GitHub::Limiters::Renderer` will intercept all responses
    # with a 429 status code, render it's own version of content, and force the
    # status code to 403. However, that middleware is not wired up in
    # integration tests so we do the full renders below so we can test the
    # responses even though they'll be replaced in production. If we ever
    # needed to force our content and status code to carry through in
    # production we could uncomment the line below which would cause
    # `GitHub::Limiters::Renderer` to let our responses pass through unaltered.
    #
    # env["limiter.renderer.allow_body"] = true

    if self.class <= ActionController::Base
      # Halt the request using ActionController#render
      halt_action_controller!(limiter_name) and return
    elsif self.class <= Sinatra::Base
      # Halt the request using Sinatra::Base#halt
      halt_sinatra_app!(limiter_name)
    else
      raise NotImplementedError
    end
  end

  private

  def log_search_rate_limiter_halt(scope, limiter_name)
    T.bind(self, T.untyped)
    logging_limit_message = "#{scope}/#{limiter_name}"

    # Log to splunk as a limited request
    if log_data ||= request.env[Rack::RequestLogger::APPLICATION_LOG_DATA]
      log_data["gh.rate_limit.secondary.limit_reason"] = logging_limit_message
    end

    # Add to request hydro payload
    if hydro_payload ||= request.env[GitHub::HydroMiddleware::PAYLOAD]
      hydro_payload["secondary_rate_limit_reason"] = logging_limit_message
    end

    GitHub.logger.info "rate limited by #{limiter_name}: #{request.fullpath}"

    # These headers are stripped by haproxy on the way out. `GH_LIMITED_GROUP`
    # is required to ensure `GitHub::Limiters::Renderer` renders the right
    # content type in production.
    headers[GitHub::Middleware::Constants::GH_LIMITED_GROUP] = scope
    headers[GitHub::Middleware::Constants::GH_LIMITED_BY] = limiter_name
  end

  # Mimics GitHub::RateLimitedRequest#render_rate_limited w/ some customization
  def halt_action_controller!(limiter_name)
    T.bind(self, T.untyped)
    return if performed?

    log_search_rate_limiter_halt("app", limiter_name)

    # `GitHub::Limiters::Renderer` will replace this content and change the
    # status code to 403 in production. We do the full render here for testing.
    filename = "429#{"-enterprise" if GitHub.enterprise?}.html"
    render file: Rails.root.join("public", filename),
           layout: false, formats: [:html], status: 429
  end

  # Mix of logging behavior from GitHub::RateLimitedRequest#render_rate_limited
  # to match behavior in frontend controllers, plus error message logic
  # extracted from GitHub::Limiters::Renderer to mimic other API rate limiters,
  # but not Api::App::RateLimitDependency#ensure_request_is_within_rate_limit!
  # as that sets headers specific to the primary rate limit.
  def halt_sinatra_app!(limiter_name)
    log_search_rate_limiter_halt("api", limiter_name)

    # `GitHub::Limiters::Renderer` will replace this content and change the
    # status code to 403 in production. We do the full render here for testing.
    options_file = File.read(Rails.root.join("public", "429.json"))
    options_hash = JSON.parse(options_file).symbolize_keys
    T.bind(self, T.untyped)
    deliver_error! 429, options_hash
  end

  # Prevent remaining registered rate limiters from running in this request
  def search_rate_limiters_halt!
    @search_rate_limiters_halted = true
  end

  def search_rate_limiters_halted?
    @search_rate_limiters_halted == true
  end

  def search_rate_limiter_states
    @search_rate_limiter_states ||= {}
  end

  def search_rate_limiters_reset!
    # Setup a statemachine for tracking each limiter in this request
    limiters = self.class.search_rate_limiters.keys
    @search_rate_limiter_states = limiters.inject({}) do |states, limiter|
      states[limiter] = SearchRateLimitState.new
      states
    end
  end

  # Currently route filtering is limited to Rails controller actions. We could
  # support Sinatra routes here if we needed to.
  def search_rate_limit_action?(limiter_options)
    rate_limit_only   = limiter_options[:only]
    rate_limit_except = limiter_options[:except]

    T.bind(self, T.untyped)
    if defined?(action_name) && rate_limit_except.any?
      !rate_limit_except.include?(action_name.to_sym)
    elsif defined?(action_name) && rate_limit_only.any?
      rate_limit_only.include?(action_name.to_sym)
    else
      true
    end
  end

  # Exclude requests from rate limiting if an `:if` option was provided and the
  # specified method returns false, or if an `:unless` was provided and the
  # specified method returns true
  def search_rate_limit_request?(limiter_options)
    rate_limit_if = limiter_options[:if]
    rate_limit_unless = limiter_options[:unless]

    passes_if = if rate_limit_if.blank?
      true
    else
      send(rate_limit_if)
    end

    passes_unless = if rate_limit_unless.blank?
      true
    else
      !send(rate_limit_unless)
    end

    search_rate_limit_action?(limiter_options) && passes_if && passes_unless
  end

  # This will call the methods registered via `:start_request` for each limiter
  # in order of registration. Your `:start_request` method should either return
  # an `:OK` to indicate it's safe to continue, or call `render`, `redirect`,
  # `halt`, etc. to interrupt the request. Returning any other value is
  # considered permission to halt further processing, but no other action will
  # be taken automatically.
  def search_rate_limiters_start
    # Make idempotent
    return if defined?(@search_rate_limiters_started)
    @search_rate_limiters_started = true

    # Heartbeat
    GitHub.dogstats.increment("search.ratelimitregistry.start", sample_rate: 0.01)

    # Reset the state machine for the request
    search_rate_limiters_reset!

    # Call :start_request method on each limiter in registration order
    self.class.search_rate_limiters.each do |limiter, options|
      # Do not run this rate limiter if a previous rate limiter called `halt!`
      return if search_rate_limiters_halted?

      # Mark that the limiter is being processed
      state = search_rate_limiter_states[limiter]
      state.start!

      unless search_rate_limit_request?(options)
        state.skip!
        next
      end

      status = if options[:start_request].is_a?(Symbol)
        send(options[:start_request], limiter, state)
      else
        # If no `:start_request` method was registered assume it's OK to proceed
        :OK
      end

      if status == :OK
        # Mark the limiter as determining it's OK to proceed
        state.ok!
      else
        # Mark the limiter as determining processing of other registered rate
        # limiters should halt. Note that no special handling of the request is
        # performed here; it's up to the limiter to call `render`, `redirect`,
        # `halt`, etc. as necessary. `render_search_rate_limiter_halt!` defined
        # above is a convenience method that callers can use for this purpose.
        state.halt!
        search_rate_limiters_halt!
      end
    end

    # Return false if any rate limiters were halted. This doesn't do anything
    # automatically as Sinatra::Base will ignore any return in a `before`
    # filter, and ActionController::Base doesn't do anything special in an
    # `around` block unless we explicitly return early, which we don't because
    # we instead check for `performed?` before yielding to the rest of the
    # action.
    !search_rate_limiters_halted?
  end

  # This will call the methods registered via `finish_request` for each limiter
  # in order of registration. It is too late at this point for any limiter to
  # halt the execution of a request, but if your limiter needs to do any post
  # request processing this is where it will happen.
  #
  # Note that this is called for all limiters regardless of whether a previous
  # limiter was `halt!`ed. You can use the `state` argument to determine the
  # state of a given limiter before performing any preprocessing.
  def search_rate_limiters_finish
    # Make idempotent
    return if defined?(@search_rate_limiters_finished)
    @search_rate_limiters_finished = true

    # Heartbeat
    GitHub.dogstats.increment("search.ratelimitregistry.finish", sample_rate: 0.01)

    self.class.search_rate_limiters.each do |limiter, options|
      next unless search_rate_limit_request?(options)

      if options[:finish_request].is_a?(Symbol)
        state = search_rate_limiter_states[limiter]
        send(options[:finish_request], limiter, state)
      end
    end
    true
  end

  def search_rate_limiters_around
    begin
      search_rate_limiters_start
      yield unless T.cast(self, T.untyped).performed?
    ensure
      search_rate_limiters_finish
    end
  end

  def search_rate_limiters_enabled?
    GitHub.rate_limiting_enabled?
  end
end
