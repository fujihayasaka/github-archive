# typed: true
# frozen_string_literal: true

require "faraday"
require "typhoeus"
require "typhoeus/adapters/faraday"
require "tsort"

module GitHub
  module FaradayClient
    autoload :Internal, "github/faraday_client/internal"
    autoload :External, "github/faraday_client/external"

    RETRIABLE_TWIRP_PATH_REGEX = Regexp.compile(%r{\A/twirp/.*/(Get|List)[^/]*\z}).freeze

    RETRY_TWIRP_LAMBDA = lambda do |env, _exception|
      env.method == :post && RETRIABLE_TWIRP_PATH_REGEX.match?(env.url.path)
    end

    # For more information about why these retry defaults where chosen, refer to
    # https://thehub.github.com/epd/engineering/dev-practicals/github-http-config-defaults/
    DEFAULT_RETRY_OPTIONS = {
      max: 2,
      interval: 0.05,
      interval_randomness: 0.5,
      backoff_factor: 2,
      exceptions: [
        Errno::ETIMEDOUT,
        "Timeout::Error",
        Faraday::TimeoutError,
        Faraday::ConnectionFailed,
        Faraday::RetriableResponse,
      ],
      retry_statuses: [502, 503],
      retry_if: RETRY_TWIRP_LAMBDA
    }.freeze

    # For more information about why these circuit breaker defaults were chosen,
    # refer to https://github.com/github/reliability-engineering/discussions/279
    DEFAULT_RESILIENT_OPTIONS = {
      options: {
        request_volume_threshold: 2,
        error_threshold_percentage: 60,
      }
    }

    INVALID_MIDDLEWARE = {
      Faraday::Request::Retry => "Please use GitHub::FaradayMiddleware::Retries instead of the default retry middleware."
    }.freeze

    InvalidMiddlewareError = Class.new(StandardError)
    MiddlewareOrderingError = Class.new(StandardError)

    HandlerOptions = Struct.new(:args, :block, :default_options, :factory_overrides, :enabled)

    # Create a ::Faraday::Connection with defaults for requests internal to GitHub.
    #
    # @param client_name: The name of the client, used for telemetry.
    #
    # Internal requests are requests to other GitHub services, hosted either in our datacenters
    # or by GitHub in a cloud.
    #
    # This includes by default, in the order they show up in the final middleware chain:
    #  - GitHub::FaradayMiddleware::TenantContext
    #  - GitHub::FaradayMiddleware::RequestID
    #  - GitHub::FaradayMiddleware::DataDog
    #  - GitHub::FaradayMiddleware::Retries
    #  - GitHub::FaradayMiddleware::Resilient
    #
    # **Default** timeouts based on observed GitHub behavior and intended to keep
    # total request time with retries under 5 seconds.  GitHub defaults will be used unless
    # overridden by options.
    #
    # Returns a typhoeus connection, which cannot be overridden.
    #
    # Accepts a block to configure the connection per Faraday's API, but does
    # not allow setting the adapter.
    #
    # To configure custom settings for the default middleware above, simply call
    # `conn.use` with that middleware as you would on a normal Faraday connection.
    #
    # Additional middleware may be configured in the block if desired. The
    # factory will attempt to ordering the middleware in the order they appear
    # as `conn.use` calls in the block. However, the default middleware will
    # maintain their relative ordering as specified above. Some middleware
    # depend on coming after other middleware in the chain; for example, the
    # IncreasingTimeout middleware must come after the Retries middleware to be
    # effective. There are two ways to accomplish this with this factory. One is
    # to just call `use`` on both the middleware in the order you want them to
    # be in the chain. Example:
    #
    # GitHub::FaradayClient.internal("my_client") do |conn|
    #   conn.use GitHub::FaradayMiddleware::Retries
    #   conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
    # end
    #
    # The other way is to use the `order_after` method on the factory to specify
    # a relative ordering of the default middleware. Example:
    #
    # GitHub::FaradayClient.internal("my_client") do |conn|
    #   conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
    #   conn.order_after(GitHub::FaradayMiddleware::IncreasingTimeout, GitHub::FaradayMiddleware::Retries)
    # end
    #
    # This option is helpful for when you don't need to change the options
    # provided to a middleware already existing in the chain, but you want to
    # add a new middleware with an ordering relative to that existing
    # middleware.
    def self.internal(client_name, base_url = nil, options = nil)
      raise ArgumentError.new("client_name is required") if client_name.blank?

      conn = ::Faraday::Connection.new(base_url, options) do |conn|
        conn.options.timeout ||= 1.3 #1300ms
        conn.options.open_timeout ||= 0.15 #150ms

        # Note to maintainers: Adding a middleware to the required_middlewares
        # passed to the delegator will cause it to be silently re-ordered
        # relative to the other required middlewares, towards the end of the
        # middleware chain. This may cause unexpected and/or breaking behavior
        # for existing clients that are already using the middleware being
        # added. For now, please add new middlewares to the clients themselves
        # and not the factory.
        # Please see https://github.com/github/reliability-engineering/issues/297
        # for more information on how we plan to deal with this.
        delegator = GitHubFaradayConnectionDelegator.new(conn, default_middlewares: {
          GitHub::FaradayMiddleware::RequestID => HandlerOptions.new,
          GitHub::FaradayMiddleware::TenantContext => HandlerOptions.new,
          GitHub::FaradayMiddleware::Datadog => HandlerOptions.new(
            default_options: { stats: GitHub.dogstats },
            factory_overrides: { service_name: client_name },
          ),
          GitHub::FaradayMiddleware::Retries => HandlerOptions.new(
            default_options: DEFAULT_RETRY_OPTIONS,
            factory_overrides: { client_name: client_name },
          ),
          GitHub::FaradayMiddleware::Resilient => HandlerOptions.new(
            default_options: DEFAULT_RESILIENT_OPTIONS,
            factory_overrides: { name: client_name },
          ),
        })

        delegator.order(
          GitHub::FaradayMiddleware::Datadog,
          after: [GitHub::FaradayMiddleware::TenantContext, GitHub::FaradayMiddleware::RequestID]
        )
        delegator.order(
          GitHub::FaradayMiddleware::DatadogAsync,
          after: [GitHub::FaradayMiddleware::TenantContext, GitHub::FaradayMiddleware::RequestID]
        )

        delegator.order(
          GitHub::FaradayMiddleware::AsyncDuration,
          after: [GitHub::FaradayMiddleware::TenantContext, GitHub::FaradayMiddleware::DatadogAsync]
        )

        delegator.order(
          GitHub::FaradayMiddleware::Retries,
          after: [GitHub::FaradayMiddleware::Datadog, GitHub::FaradayMiddleware::AsyncDuration]
        )

        delegator.order(
          GitHub::FaradayMiddleware::Resilient,
          after: [GitHub::FaradayMiddleware::Retries]
        )

        yield(delegator) if block_given?

        delegator.disable GitHub::FaradayMiddleware::Datadog if delegator.has_middleware?(GitHub::FaradayMiddleware::DatadogAsync)
        delegator.finalize

        conn.adapter :typhoeus, *delegator.adapter_options
      end
    end

    # Create a ::Faraday::Connection:: with defaults for requests external to GitHub.
    #
    # @param client_name The name of the client, used for telemetry.
    #
    # External requests are requests to services outside of GitHub, such as calls to Microsoft or DataDog.
    #
    # This includes by default:
    #  - External communication proxy if configured
    #  - DataDog middleware
    #  - Retry middleware
    #  - Resilient circuit-breaker middleware
    #
    # **Default** timeouts based on observed GitHub behavior and intended to keep
    # total request time with retries under 5 seconds. GitHub defaults will be used unless
    # overridden by options.
    #
    # To configure custom settings for the default middleware above, simply call
    # `conn.use` with that middleware as you would on a normal Faraday connection.
    #
    # Additional middleware may be configured in the block if desired. The
    # factory will attempt to ordering the middleware in the order they appear
    # as `conn.use` calls in the block. However, the default middleware will
    # maintain their relative ordering as specified above. Some middleware
    # depend on coming after other middleware in the chain; for example, the
    # IncreasingTimeout middleware must come after the Retries middleware to be
    # effective. There are two ways to accomplish this with this factory. One is
    # to just call `use`` on both the middleware in the order you want them to
    # be in the chain. Example:
    #
    # GitHub::FaradayClient.internal("my_client") do |conn|
    #   conn.use GitHub::FaradayMiddleware::Retries
    #   conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
    # end
    #
    # The other way is to use the `order_after` method on the factory to specify
    # a relative ordering of the default middleware. Example:
    #
    # GitHub::FaradayClient.internal("my_client") do |conn|
    #   conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
    #   conn.order_after(GitHub::FaradayMiddleware::IncreasingTimeout, GitHub::FaradayMiddleware::Retries)
    # end
    #
    # This option is helpful for when you don't need to change the options
    # provided to a middleware already existing in the chain, but you want to
    # add a new middleware with an ordering relative to that existing
    # middleware.
    def self.external(client_name, base_url = nil, options = nil)
      raise ArgumentError.new("client_name is required") if client_name.blank?

      conn = ::Faraday::Connection.new(base_url, options) do |conn|
        conn.options.timeout ||= 1.1 #1100ms
        conn.options.open_timeout ||= 0.3 #300ms
        conn.proxy = GitHub.external_communication_proxy_host if conn.proxy.nil?

        delegator = GitHubFaradayConnectionDelegator.new(conn, default_middlewares: {
          GitHub::FaradayMiddleware::Datadog => HandlerOptions.new(
            default_options: { stats: GitHub.dogstats },
            factory_overrides: { service_name: client_name },
          ),
          GitHub::FaradayMiddleware::Retries => HandlerOptions.new(
            default_options: DEFAULT_RETRY_OPTIONS,
            factory_overrides: { client_name: client_name },
          ),
          GitHub::FaradayMiddleware::Resilient => HandlerOptions.new(
            default_options: DEFAULT_RESILIENT_OPTIONS,
            factory_overrides: { name: client_name },
          ),
        })

        delegator.order(
          GitHub::FaradayMiddleware::Retries,
          after: [GitHub::FaradayMiddleware::Datadog, GitHub::FaradayMiddleware::DatadogAsync]
        )

        delegator.order(
          GitHub::FaradayMiddleware::Resilient,
          after: [GitHub::FaradayMiddleware::Retries]
        )

        yield(delegator) if block_given?

        delegator.disable GitHub::FaradayMiddleware::Datadog if delegator.has_middleware?(GitHub::FaradayMiddleware::DatadogAsync)
        delegator.finalize

        conn.adapter :typhoeus, *delegator.adapter_options
      end
    end

    class GitHubFaradayConnectionDelegator < SimpleDelegator
      include TSort

      def initialize(conn, default_middlewares:)
        super(conn)
        @after_relationships = Hash.new { |hash, key| hash[key] = [] }
        @middleware_options = Hash.new { |hash, key| hash[key] = HandlerOptions.new(enabled: true) }
        @default_middlewares = default_middlewares
        @adapter_options = []
      end

      # Set adapter options. This must be an array so that it can be passed,
      # using a splat, as extra args to the underlying 'conn.adapter :typhoeus'
      # statement.
      #
      # See ethon's lib/ethon/curls/options.rb for available options.
      #
      # Example:
      #   conn.adapter_options = [{ http_version: :httpv1_1 }]
      def adapter_options=(options)
        Kernel.raise ArgumentError.new("adapter_options must be an array") unless options.is_a?(Array)
        @adapter_options = options
      end

      def adapter_options
        @adapter_options
      end

      def adapter(...)
        Kernel.raise NotImplementedError.new("Cannot change adapter on a GitHubFaradayConnectionDelegator")
      end

      def has_middleware?(handler_klass)
        @middleware_options.key?(handler_klass)
      end

      def use(klass, *args, &block)
        @middleware_options[klass].args = args
        @middleware_options[klass].block = block
      end

      # Orders the given middleware relative to the list of `before` and
      # `after`.  The middleware is ordered to occur before any of the
      # middleware in the `before` list, and after any of the middleware in the
      # `after` list.  Validation for cycles is done when building the
      # middleware chain.
      def order(middleware_klass, before: [], after: [])
        # ensures `before` is always an array.
        [*before].each do |other|
          next if @after_relationships[other].include?(middleware_klass)
          @after_relationships[other] << middleware_klass
        end

        # ensures `after` is always an array.
        [*after].each do |other|
          next if @after_relationships[middleware_klass].include?(other)
          @after_relationships[middleware_klass] << other
        end
      end

      def disable(klass)
        @middleware_options[klass].enabled = false
      end

      def finalize
        check_for_invalid_middlewares

        @default_middlewares.each do |klass, options|
          @middleware_options[klass].default_options = options.default_options
          @middleware_options[klass].factory_overrides = options.factory_overrides
        end

        sorted_middlewares = begin
          tsort
        rescue TSort::Cyclic => exception
          Kernel.raise MiddlewareOrderingError.new("Circular ordering constraint in middleware chain: #{exception.message}")
        end
        sorted_middlewares.each do |klass|
          options = @middleware_options[klass]
          next unless options.enabled

          if options.default_options.nil? && options.factory_overrides.nil?
            __getobj__.use klass, *options.args, &options.block
          else
            # Note: The factory_overrides are only used if either default options or
            # user options are provided.  The assumption is that if neither of those
            # are present, then the middleware does not accept arguments.
            user_overrides = options.args&.first
            middleware_options = options.default_options.nil? ? user_overrides : options.default_options.deep_merge(user_overrides || {})

            if middleware_options.nil?
              __getobj__.use klass, nil, &options.block
            else
              __getobj__.use klass, middleware_options.deep_merge(options.factory_overrides || {}), &options.block
            end
          end
        end
      end

      private

      def tsort_each_node(&block)
        @middleware_options.select { |_, options| options.enabled }.each_key(&block)
      end

      def tsort_each_child(node, &block)
        @after_relationships[node].filter do |dep|
          @middleware_options.key?(dep) && @middleware_options[dep].enabled
        end.each(&block)
      end

      def check_for_invalid_middlewares
        errors = __getobj__.builder.handlers.filter_map { |h| INVALID_MIDDLEWARE[h.klass] }
        Kernel.raise InvalidMiddlewareError.new(errors.join(" ")) if errors.any?
      end
    end
  end
end
