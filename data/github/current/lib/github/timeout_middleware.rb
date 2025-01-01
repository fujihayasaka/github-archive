# typed: true
# frozen_string_literal: true

require_relative "./resilient/circuit_breaker/active_tracker"

module GitHub
  class TimeoutMiddleware
    # Note: this error is only created by the GitHub::TimeoutMiddleware, but is
    # not raised and can't be rescued. After being created, the error is logged
    # and we exit the process.
    class RequestTimeout < StandardError
      attr_accessor :timeout
      attr_reader :env, :start

      def self.is_graphql_request?(env)
        !!(env["REQUEST_PATH"] =~ ::Api::GraphQL::PATH_REGEX)
      end

      def self.for_thread(thread, timeout, env)
        if is_graphql_request?(env)
          klass = PlatformTimeout
        else
          klass = RequestTimeout
        end

        klass.new(env).tap do |ex|
          ex.set_backtrace(thread.backtrace)
          ex.timeout = timeout
        end
      end

      def initialize(env)
        @env = env
        @start = GitHub::TaggingHelper.request_start(env) || Process.clock_gettime(Process::CLOCK_MONOTONIC)

        if params = GitHub::TaggingHelper.path_parameters(env)
          super("#{GitHub::TaggingHelper.category(env)}:#{params[:controller]}##{params[:action]}")
        elsif params = GitHub::TaggingHelper.api_parameters(env)
          super("#{params[:app]} #{params[:route]}")
        end
      end

      def notify_watchers
        GitHub::TimeoutMiddleware.watchers(env).each { |watcher| watcher.timeout(env) }
      end

      def report(thread)
        # Ideally we wouldn't query in this thread at all, but if we do it must
        # be reading. Our primary pool size is 1, so using the writing role in
        # this thread is likely to raise ActiveRecord::ConnectionTimeoutError.
        ActiveRecord::Base.connected_to(role: :reading) do
          report_to_failbot(thread)
          report_pull_request_timeout
          log_request
          record_stats
          notify_watchers
          report_to_hydro
          shutdown_tracer(thread)
          emit_circuit_breaker_telemetry(thread)
          # ensure stats collected by watchers are sent to DataDog
          flush_stats
        end
      end

      def shutdown_tracer(thread)
        error_status = OpenTelemetry::Trace::Status.error("Request Timeout")

        [GitHub::Telemetry::Hacks.current_span_from(thread), GitHub.current_span].uniq.compact.each do |span|
          begin
            span.record_exception(self)
            span.status = error_status
            span.finish
          rescue StandardError => e
            GitHub.dogstats.increment("gh.otel.hacks.error", tags: { "exception.type" => e.class.name })
          end
        end
        GitHub.shutdown_tracer
      end

      def emit_circuit_breaker_telemetry(thread)
        circuit_breakers = Resilient::CircuitBreaker::ActiveTracker.active_circuit_breakers(thread)

        return if circuit_breakers.empty?

        GitHub.logger.error(
          "Request timedout with active circuit breakers.",
          { "gh.circuit_breaker.names" => circuit_breakers }
        )
      end

      # RequestTimeout can sometimes trigger inside code that isn't designed to
      # gracefully handle being interrupted. This can cause corruption of state
      # that carries through to subsequent requests.
      #
      # Because it may not be safe to process more requests in this worker
      # process, we just report the timeout to Failbot and die.
      def report_and_die!(thread)
        report(thread)
      ensure
        exit!
      end

      # TimeoutMiddleware exits before HydroMiddleware has a chance to finalize
      # and publish the request payload, so we force HydroMiddleware to publish
      # the incomplete payload here.
      def report_to_hydro
        return unless GitHub.hydro_enabled? && !env[GitHub::HydroMiddleware::PAYLOAD].nil?

        env[GitHub::HydroMiddleware::PAYLOAD].merge!({
          timed_out: true,
          request_category: category,
          current_user: GitHub.context[:actor],
          current_user_id: GitHub.context[:actor_id],
        })

        GitHub::HydroMiddleware.record_request(env)
        GitHub.close_hydro(timeout: 1)
      end

      private

      def filtered_request_body
        body = GitHub.context[:filtered_request_body]
        return nil unless body.present?
        body.squish
      end

      def failbot_context
        context = {
          app: "github-timeout",
          "gh.request.timeout.limit": timeout,
          "gh.request.timer_stats": GitHub.request_timer.formatted_stats,
          rollup: Digest::SHA256.hexdigest(message),
        }
        if singleton = env[Rack::ProcessUtilization::ENV_KEY]
          singleton.stats_for_failbot_context.merge(context)
        else
          context
        end
      end

      def report_to_failbot(thread)
        Failbot.report_from_thread(thread, self, failbot_context)
      end

      def log_request
        Rack::RequestLogger.log(env, 500, {}, timeout, timeout: true)
      end

      def category
        @category ||= GitHub::TaggingHelper.category(env)
      end

      def record_stats
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed = (now - start)
        GitHub.stats.increment("unicorn.#{category}.request_timeout") if GitHub.enterprise?
        GitHub.stats.increment("unicorn.#{GitHub.rails_version_key}.#{category}.request_timeout") if GitHub.enterprise?

        controller = GitHub::TaggingHelper.controller(env)
        action = GitHub::TaggingHelper.action(env)
        method = GitHub::TaggingHelper.request_method(env)
        catalog_service = GitHub::TaggingHelper.catalog_service(env)

        tags = []

        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::RAILS_VERSION_TAG, GitHub.rails_version_key)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CATEGORY_TAG, category)
        GitHub::TaggingHelper.add_tag(tags, "request_category", category)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CATALOG_SERVICE_TAG, catalog_service)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CONTROLLER_TAG, controller) if controller
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::ACTION_TAG, action) if action
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::METHOD_TAG, method) if method

        GitHub.dogstats.distribution("request.dist.timeout", elapsed, tags: tags)

        # page timeout counts as a failed request, update any subscribed availability slos
        GitHub::TaggingHelper.tracked_availability_slos(env).each do |name|
          GitHub.dogstats.increment("#{catalog_service}.slo", tags: ["success:false", "name:availability/#{name}"])
        end

        # Report query stats for the request so they aren't lost in timeout
        # requests where they're extremely valuable to have.
        GitHub::MysqlInstrumenter.report_stats(controller, action, method, catalog_service)
      end

      def flush_stats
        # Flush stats before quitting
        GitHub.stats.flush_all if GitHub.enterprise?
        GitHub.dogstats.flush(sync: true)
      end

      def report_pull_request_timeout
        params = GitHub::TaggingHelper.path_parameters(env)
        return unless params
        return unless params[:controller] == "pull_requests" && params[:action] == "show"
        reason = env["pull_request.timeout_reason"] || "other"
        exception_class = "PullRequestTimeout::#{reason.classify}"
        Failbot.report_trace(self, failbot_context.merge({
          "gh.timeout.reason": exception_class,
          rollup: Digest::SHA256.hexdigest(exception_class),
        }))
      end
    end

    class PlatformTimeout < RequestTimeout; end

    attr_reader :app

    WATCHERS = "github.timeout_watchers".freeze

    # Internal:
    def self.watchers(env)
      env[WATCHERS] ||= []
    end

    # Public:
    def self.notify(env, watcher)
      watchers(env) << watcher
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      return app.call(env) unless GitHub.timeout_middleware_enabled?

      request_thread = Thread.current
      otel_context = OpenTelemetry::Context.current

      timeout = GitHub.request_timeout(env)
      timer_thread = Thread.new do # rubocop:disable GitHub/ThreadUse
        sleep(timeout)
        OpenTelemetry::Context.with_current(otel_context) do
          exception = RequestTimeout.for_thread(request_thread, timeout, env)
          exception.report_and_die!(request_thread)
        end
      end

      GitHub::RequestDurationManager.with_budget_control(total_window_ms: timeout * 1000) do
        app.call(env)
      end
    ensure
      timer_thread&.kill
    end
  end
end
