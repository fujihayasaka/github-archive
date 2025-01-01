# typed: true
# frozen_string_literal: true

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

      def report_timeout_duration(timeout_start_time)
        timeout_total_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - timeout_start_time) * 1000 # record time in milliseconds
        GitHub.dogstats.distribution("request.timeout_middleware.dist", timeout_total_time)
      end

      def with_segment_timing(segment_tag)
        if emit_timing_metrics?
          segment_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
          segment_duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - segment_start_time) * 1_000_000 # microseconds
          GitHub.dogstats.distribution("request.timeout_middleware.segment.dist", segment_duration, tags: [segment_tag])
          segment_duration
        else
          yield
          0
        end
      end

      def emit_timing_metrics?
        return @emit_timing_metrics if defined?(@emit_timing_metric)
        @emit_timing_metrics = rand < GitHub.timeout_middleware_timing_metrics_sample_rate
      end

      def report(thread, timeout_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC))
        # Ideally we wouldn't query in this thread at all, but if we do it must
        # be reading. Our primary pool size is 1, so using the writing role in
        # this thread is likely to raise ActiveRecord::ConnectionTimeoutError.
        ActiveRecord::Base.connected_to(role: :reading) do
          total_segments_time = 0
          total_segments_time += with_segment_timing("segment:record_stats") { record_stats }
          total_segments_time += with_segment_timing("segment:report_to_failbot") { report_to_failbot(thread) }
          total_segments_time += with_segment_timing("segment:report_pull_request_timeout") { report_pull_request_timeout }
          total_segments_time += with_segment_timing("segment:log_request") { log_request }
          total_segments_time += with_segment_timing("segment:notify_watchers") { notify_watchers }
          total_segments_time += with_segment_timing("segment:report_to_hydro") { report_to_hydro }
          total_segments_time += with_segment_timing("segment:shutdown_tracer") { shutdown_tracer }
          # ensure stats collected by watchers are sent to DataDog
          total_segments_time += with_segment_timing("segment:flush_stats") { flush_stats }

          timeout_total_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - timeout_start_time) * 1000 # record total time in milliseconds
          GitHub.dogstats.distribution("request.timeout_middleware.dist", timeout_total_time)

          if emit_timing_metrics?
            total_untracked_time = timeout_total_time * 1000 - total_segments_time # segments time is in microseconds
            GitHub.dogstats.distribution("request.timeout_middleware.segment.dist", total_untracked_time, tags: ["segment:untracked"])
          end

          # flush again to capture timeout reporting duration metric
          flush_stats
        end
      end

      def shutdown_tracer
        error_status = OpenTelemetry::Trace::Status.error("Request Timeout")
        span = GitHub.current_span

        begin
          span.record_exception(self)
          span.status = error_status
          span.finish
        rescue StandardError => e
          GitHub.dogstats.increment("gh.otel.hacks.error", tags: { "exception.type" => e.class.name })
        end
        GitHub.shutdown_tracer
      end

      # RequestTimeout can sometimes trigger inside code that isn't designed to
      # gracefully handle being interrupted. This can cause corruption of state
      # that carries through to subsequent requests.
      #
      # Because it may not be safe to process more requests in this worker
      # process, we just report the timeout to Failbot and die.
      def report_and_die!(thread, timeout_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC))
        report(thread, timeout_start_time)
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
        is_react = GitHub::TaggingHelper.is_react?(env)
        logged_in = GitHub::TaggingHelper.logged_in(env)

        tags = []

        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::RAILS_VERSION_TAG, GitHub.rails_version_key)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CATEGORY_TAG, category)
        GitHub::TaggingHelper.add_tag(tags, "request_category", category)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CATALOG_SERVICE_TAG, catalog_service)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::CONTROLLER_TAG, controller) if controller
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::ACTION_TAG, action) if action
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::METHOD_TAG, method) if method
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::IS_REACT_TAG, is_react) if is_react
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::LOGGED_IN_TAG, logged_in) if logged_in
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::STATUS_TAG, 502)
        GitHub::TaggingHelper.add_tag(tags, GitHub::TaggingHelper::STATUS_RANGE_TAG, GitHub::TaggingHelper::STATUS_RANGE_5XX)

        GitHub.dogstats.distribution("request.dist.timeout", elapsed, tags: tags)

        # page timeout counts as a failed request, update any subscribed availability slos
        GitHub::TaggingHelper.tracked_availability_slos(env).each do |name|
          GitHub.dogstats.increment("#{catalog_service}.slo", tags: ["success:false", "name:availability/#{name}"])
        end

        stats = {
          request_method: method,
          action: action,
          controller: controller,
          catalog_service: catalog_service,
        }

        tags_cache = DatadogTagsCache.new({
          TaggingHelper::METHOD_TAG          => method,
          TaggingHelper::CONTROLLER_TAG      => controller,
          TaggingHelper::ACTION_TAG          => action,
          TaggingHelper::CATALOG_SERVICE_TAG => catalog_service,
        })

        # Report rpc stats for the request so they aren't lost in timeout
        # requests where they're extremely valuable to have.
        GitHub::Middleware::Stats::Tracker::Rpc.track(GitHub.dogstats, env, stats, tags_cache)
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
        timeout_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        GitHub::DataCollector.with_collector_thread(request_thread) do
          OpenTelemetry::Context.with_current(otel_context) do
            exception = RequestTimeout.for_thread(request_thread, timeout, env)
            exception.report_and_die!(request_thread, timeout_start_time)
          end
        end
      end

      GitHub::RequestDurationManager.with_budget_control(total_window_ms: (timeout * 1000).to_i) do
        app.call(env)
      end
    ensure
      timer_thread&.kill
    end
  end
end
