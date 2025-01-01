# typed: true
# frozen_string_literal: true

require "unicorn/process_name"

module Rack
  # Middleware that tracks the amount of time this process spends processing
  # requests, as opposed to being idle waiting for a connection. Statistics
  # are dumped to rack.errors every 5 minutes.
  #
  # This middleware should be thread safe. Do not add anything that is not
  # thread safe to this middleware.
  #
  # Even within Unicorn, thread safety is a relevant concern, also see
  # https://github.blog/2021-03-18-how-we-found-and-fixed-a-rare-race-condition-in-our-session-handling/
  # for an example of what can go wrong otherwise.
  class ProcessUtilization
    DEFAULT_STATSD_SAMPLE_RATE = 0.2

    class SlowRequest < StandardError
      def initialize(action, cpu, idle, real)
        super("#{action} Real: %.2fms (CPU: %.2fms / Idle: %.2fms)" % [real, cpu, idle])
      end
    end

    class ElastomerTracker
      def self.build
        if defined? Elastomer
          new
        else
          NullTracker.new
        end
      end

      def initialize
        Elastomer::QueryStats.instance.track = true
      end

      def enabled?
        true
      end

      def count
        stats.count
      end

      def time
        stats.time
      end

      def reset
        stats.clear
      end

      private

      def stats
        Elastomer::QueryStats.instance
      end
    end

    class NullTracker
      def enabled?
        false
      end

      def reset
      end
    end

    attr_reader :gc_info, :stats

    def initialize(app, domain, revision, opts = {})
      @app = app
      @domain = domain
      @revision = revision
      @window = opts[:window] || 100
      @horizon = nil
      @active_time = nil
      @requests = nil
      @total_requests = 0
      @worker_number = nil

      setup_stats(opts[:stats], opts[:dogstats])
    end

    def setup_stats(stats, dogstats_or_block)
      @stats = stats
      @gc_info = NullTracker.new
      @elastomer_tracker = NullTracker.new
      unless @stats
        @track_mysql = @track_graphql = @track_gitrpc = @track_redis = @track_cache = @track_memcached = @track_markdown = false
        @track_render = false
        @track_tested_features = false
        return
      end

      if dogstats_or_block.respond_to?(:call)
        @dogstats_block = dogstats_or_block
      else
        @dogstats_instance = dogstats_or_block
      end
      return unless dogstats_or_block

      @gc_info = GitHub::DataCollector::GCStatsCollector.get_instance

      @hostname ||= GitHub.local_host_name_short
      @track_cpu             = true if defined?(::Process.clock_gettime)
      @track_mysql           = defined?(GitHub::MysqlInstrumenter) && GitHub::MysqlInstrumenter.respond_to?(:query_count)
      @track_graphql         = defined?(Platform)
      @track_gitrpc          = defined?(GitRPCLogSubscriber) && GitRPCLogSubscriber.respond_to?(:rpc_count)
      @track_redis           = defined?(Redis::Client) && Redis::Client.respond_to?(:query_count)
      @track_cache           = defined?(GitHub::Cache::Client) && GitHub::Cache::Client.respond_to?(:query_count)
      @track_collectors      = defined?(GitHub::DataCollector) && GitHub::DataCollector.respond_to?(:reset_all)
      @track_markdown        = defined?(GitHub::Goomba::WarpPipeStats)
      @elastomer_tracker     = ElastomerTracker.build
      @track_aqueduct_stats  = defined?(GitHub::Aqueduct::Job)
      @track_authzd          = defined?(GitHub::AuthzdInstrumenter)
    end

    # the app's domain name - shown in proctitle
    attr_accessor :domain

    # the currently running git revision as a 7-sha
    attr_accessor :revision

    # time when we began sampling. this is reset every once in a while so
    # averages don't skew over time.
    attr_accessor :horizon

    # total number of requests that have been processed by this worker since
    # the horizon time.
    attr_accessor :requests

    # decimal number of seconds the worker has been active within a request
    # since the horizon time.
    attr_accessor :active_time

    # total requests processed by this worker process since it started
    attr_accessor :total_requests

    # the unicorn worker number
    attr_accessor :worker_number

    # the amount of time since the horizon
    def horizon_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - horizon
    end

    # decimal number of seconds this process has been active since the horizon
    # time. This is the inverse of the active time.
    def idle_time
      horizon_time - active_time
    end

    # percentage of time this process has been active since the horizon time.
    def percentage_active
      (active_time / horizon_time) * 100
    end

    # percentage of time this process has been idle since the horizon time.
    def percentage_idle
      (idle_time / horizon_time) * 100
    end

    # number of requests processed per second since the horizon
    def requests_per_second
      requests / horizon_time
    end

    # average response time since the horizon in milliseconds
    def average_response_time
      (active_time / requests.to_f) * 1000
    end

    # called exactly once before the first request is processed by a worker
    def first_request
      reset_horizon
    end

    def track_gc?
      @gc_info.enabled?
    end

    # reset various counters before the new request
    def reset_stats
      if track_graphql?
        Platform::GlobalScope.reset!
      end
      if track_es?
        @elastomer_tracker.reset
      end
      @starttime = Time.now
      @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if track_cpu?
        @cputime = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      end

      if track_aqueduct_stats?
        GitHub::Aqueduct::Job.reset_stats
      end

      if track_collectors?
        GitHub::DataCollector.reset_all
        GitHub::DataCollector.enable_all
      end
    end

    # resets the horizon and all dependent variables
    def reset_horizon
      @horizon = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @active_time = 0.0
      @requests = 0
    end

    # called immediately after a request to record statistics, update the
    # procline, and dump information to the logfile
    def record_request(response_size, status_code, env)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      diff = (now - @start)
      @active_time += diff
      @requests += 1

      if @stats
        if request_end_cpu_stats = env[GitHub::TaggingHelper::REQ_CPU_TIMES]
          cpu, idle, real = request_end_cpu_stats
        end

        if track_mysql?
          ar_count, ar_types, query_cache_hits = activerecord_stats
          mysql_count, mysql_time, query_counts = mysql_stats
        else
          mysql_count = mysql_time = -1
          query_counts = Hash.new(0)
          ar_count = ar_types = query_cache_hits = -1
        end

        if track_gitrpc?
          gitrpc_count, gitrpc_time, _ = gitrpc_stats
        else
          gitrpc_count = gitrpc_time = -1
        end

        request_category = request_category(env)
        request_categories = [request_category]

        # Keep tracking "browser_*" under "browser" too to keep our
        # historical data valid. (Ditto for "anon_*".)
        if match = request_category.match(/\A(browser|anon)_/)
          request_categories << match[1]
        end

        request_categories.each do |request_category|
          record_stats request_category, diff, response_size, status_code, env
        end

        if track_cpu? && GitHub.instrument_slow_requests?
          stats = stats_for_failbot_context.merge(response_size: response_size)
          record_request_stats(cpu, idle, real, query_counts, env, stats)
        end
      end

      Unicorn::ProcessName.instance.update(
        total_requests:,
        requests_per_second:,
        average_response_time:,
        percentage_active:
      )
      Unicorn::ProcessName.instance.setproctitle

      reset_horizon if now - horizon > @window
    rescue => boom # rubocop:todo Lint/GenericRescue
      warn "ProcessUtilization#record_request failed: #{boom.inspect}\n#{boom.backtrace.to_a.join("\n")}"
    end

    # Public: Returns all statistics as a Hash suitable for inclusion in a
    # Failbot exception context.
    def stats_for_failbot_context
      stats = {}

      stats[:"gh.system.cpu.cpu_time"], stats[:"gh.system.cpu.idle_time"], stats[:"gh.system.cpu.real_time"] = cpu_stats if track_cpu?
      stats[:"gh.system.cache.call_count"], stats[:"gh.system.cache.call_time"] = cache_stats if track_cache?
      stats[:"gh.request.es.call_count"], stats[:"gh.request.es.call_time"] = es_stats if track_es?

      if @gc_info.enabled?
        stats[:"gh.system.ruby.allocations_count"] = @gc_info.allocations
        stats[:"gh.system.ruby.gc.call_count"] = @gc_info.count
        stats[:"gh.system.ruby.gc.call_time"] = @gc_info.time
      end

      if track_gitrpc?
        stats[:"gh.request.gitrpc.call_count"], stats[:"gh.request.gitrpc.call_time"] = gitrpc_stats
        stats[:"gh.request.gitrpc.call_stats"] = format_gitrpc_call_stats(GitRPCLogSubscriber.rpc_call_stats)
      end

      stats[:"gh.request.memcached.query_count"], stats[:"gh.request.memcached.query_time"] = memcached_stats if track_memcached?

      if track_mysql?
        ar_count, ar_types, query_cache_hits = activerecord_stats
        stats[:"gh.request.ar.object_count"] = ar_count
        stats[:"gh.request.ar.object_stats"] = format_count_hash(ar_types)
        stats[:"gh.request.mysql.cache_hit_count"] = query_cache_hits
        stats[:"gh.request.mysql.call_count"], stats[:"gh.request.mysql.query_time"], query_counts = mysql_stats
        stats[:"gh.request.mysql.call_stats"] = format_count_hash(query_counts)
      end

      stats[:"gh.request.redis.call_count"], stats[:"gh.request.redis.call_time"] = redis_stats if track_redis?

      if track_graphql?
        stats[:"gh.request.graphql.query_count"] = format_graphql_queries(Platform::GlobalScope.queries.map { |q| q[:string] })
      end

      stats.each do |key, value|
        next unless key.to_s.end_with?("_time")
        stats[key] = value.round(3)
      end

      stats
    end

    def format_graphql_queries(queries)
      queries.join("#{'-' * 40}\n")
    end

    def format_count_hash(hash)
      self.class.format_count_hash(hash)
    end

    def self.format_count_hash(hash)
      lines = hash.sort_by { |_key, count| -count }.map do |key, count|
        "%7d | #{key}\n" % count
      end
      lines.join("")
    end

    def format_gitrpc_call_stats(call_stats)
      return "" if call_stats.empty?
      rows = call_stats
        .sort_by { |_command, stats| -stats.time }
        .map     { |command, stats| sprintf("%7.3f | %7d | %s\n", stats.time, stats.count, command) }
      sprintf("%7s | %7s | %s\n%s", "Seconds", "Count", "Command", rows.join(""))
    end

    def record_request_stats(cpu, idle, real, query_counts, env, opts = {})
      if real > GitHub.slow_request_threshold
        klass = SlowRequest
        if params = env && GitHub::TaggingHelper.path_parameters(env)
          app = "github-slow-request"
          rollup = "#{env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY]}:#{params[:controller]}##{params[:action]}"
        elsif params = env && GitHub::TaggingHelper.api_parameters(env)
          app = "github-slow-api-request"
          rollup = "#{params[:app]} #{params[:route]}"
        else
          return
        end

        req = klass.new(rollup, cpu * 1000, idle * 1000, real * 1000)

        opts = opts.merge(
          app: app,
          "rails.controller.name": rollup,
          rollup: Digest::SHA256.hexdigest("#{req.class}#{rollup}"),
        )

        Failbot.report!(req, opts)
      end
    end

    def record_stats(category, real, response_size, status_code, env)
      @stats.increment "unicorn.#{category}.status_code.#{status_code}.count"

      if request_end_cpu_stats = env[GitHub::TaggingHelper::REQ_CPU_TIMES]
        cpu, idle, _ = request_end_cpu_stats

        @stats.timing "unicorn.#{category}.cpu_time", cpu * 1000
        @stats.timing "unicorn.#{category}.idle_time", idle * 1000
      end

      if @gc_info.enabled?
        @stats.timing "unicorn.#{category}.gc.allocations", @gc_info.allocations
        @stats.count  "unicorn.#{category}.gc.collections", @gc_info.count
        @stats.timing "unicorn.#{category}.gc.time", @gc_info.time * 1000
        @stats.count  "unicorn.#{category}.gc.major", @gc_info.major_count
        @stats.count  "unicorn.#{category}.gc.minor", @gc_info.minor_count
      end

      if track_mysql?
        mysql_count, mysql_time = mysql_stats
        if mysql_count > 0
          @stats.count  "unicorn.#{category}.mysql.queries", mysql_count
          @stats.timing "unicorn.#{category}.mysql.time", mysql_time * 1000
        end

        ar_count, ar_types, query_cache_hits = activerecord_stats
        if ar_count > 0
          @stats.count  "unicorn.#{category}.activerecord.objs", ar_count
        end
      end

      if track_gitrpc?
        gitrpc_count, gitrpc_time = gitrpc_stats
        if gitrpc_count > 0
          @stats.count  "unicorn.#{category}.gitrpc.rpcs", gitrpc_count
          @stats.timing "unicorn.#{category}.gitrpc.time", gitrpc_time * 1000
        end
      end

      if track_cache?
        cache_count, cache_time = cache_stats
        if cache_count > 0
          @stats.count  "unicorn.#{category}.cache.queries", cache_count
          @stats.timing "unicorn.#{category}.cache.time", cache_time * 1000
        end
      end

      if track_memcached?
        memcached_count, memcached_time = memcached_stats
        if memcached_count > 0
          @stats.count  "unicorn.#{category}.memcached.queries", memcached_count
          @stats.timing "unicorn.#{category}.memcached.time", memcached_time * 1000
        end
      end

      if track_redis?
        redis_count, redis_time = redis_stats
        if redis_count > 0
          @stats.count  "unicorn.#{category}.redis.queries", redis_count
          @stats.timing "unicorn.#{category}.redis.time", redis_time * 1000
        end
      end

      if track_es?
        es_count, es_time = es_stats
        if es_count > 0
          @stats.count  "unicorn.#{category}.es.queries", es_count
          @stats.timing "unicorn.#{category}.es.time", es_time * 1000
        end
      end

      @stats.timing("unicorn.#{category}.memrss", GitHub::Memory.memrss)
      @stats.timing("unicorn.#{category}.requests_per_second", requests_per_second)

      if track_cpu?
        @stats.timing("unicorn.#{category}.response_time", real * 1000)
      end

      @stats.timing("unicorn.#{category}.response_size", response_size)
    end

    # The request's category. This may be set at any point during the request to
    # log stats under a separate category. Values include: browser, api, robot,
    # raw, feed, and other.
    #
    # To change the category, write to the process.request_category key in the Rack
    # env.
    def request_category(env)
      env && env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY] || GitHub::TaggingHelper::CATEGORY_DEFAULT
    end

    def request_category_datadog(env)
      env && env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY_DATADOG] || GitHub::TaggingHelper::CATEGORY_DEFAULT
    end

    def statsd_sample_rate(env)
      (env && env[GitHub::TaggingHelper::STATSD_SAMPLE_RATE] || DEFAULT_STATSD_SAMPLE_RATE).to_f
    end

    def track_cpu?
      @track_cpu
    end

    def track_authzd?
      @track_authzd
    end

    # CPU usage stats for the current request.
    #
    # Returns an Array of
    #   cpu  - Time spent on the CPU
    #   idle - Time spent in I/O
    #   real - Total time (idle + cpu_time)
    def cpu_stats
      cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - @cputime
      real = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start
      idle = real - cpu

      [cpu, idle, real]
    end

    def track_mysql?
      @track_mysql
    end

    # MySQL stats for the current request.
    #
    # Returns an Array of
    #   query_count - Number of mysql queries performed
    #   query_time  - A Float time in seconds spent querying
    def mysql_stats
      mysql = GitHub::MysqlInstrumenter
      [mysql.query_count, mysql.query_time, mysql.query_counts]
    end

    def track_graphql?
      @track_graphql
    end

    def graphql_stats
      graphql = Platform::GlobalScope
      [graphql.query_count, graphql.query_time]
    end

    def track_gitrpc?
      @track_gitrpc
    end

    # GitRPC stats for the current request.
    #
    # Returns an Array of
    #   rpc_count - Number of rpc queries performed
    #   rpc_time  - A Float time in seconds spent querying
    #   rpc_calls - An Array of EventTrace objects
    def gitrpc_stats
      [
        GitRPCLogSubscriber.rpc_count,
        GitRPCLogSubscriber.rpc_time,
        GitRPCLogSubscriber.rpc_calls,
      ]
    end

    def track_redis?
      @track_redis
    end

    # Redis stats for current request.
    def redis_stats
      redis = Redis::Client
      [redis.query_count, redis.query_time, redis.queries]
    end

    def track_es?
      @elastomer_tracker.enabled?
    end

    # ElasticSearch stats for the current request.
    #
    # Returns an Array of
    #   count - Number of elasticsearch queries performed
    #   time  - Float time in seconds spent querying
    def es_stats
      [@elastomer_tracker.count, @elastomer_tracker.time / 1000.0]
    end

    # Authzd stats for the current request.
    #
    # Returns an Array of
    #   count - Number of authzd requests executed
    #   time  - Float time in seconds spent querying
    def authzd_stats
      [
        GitHub::AuthzdInstrumenter.total_request_count,
        GitHub::AuthzdInstrumenter.total_request_time / 1000.0
      ]
    end

    def track_cache?
      @track_cache
    end

    # GitHub::Cache stats for current request.
    def cache_stats
      cache = GitHub::Cache::Client
      [cache.query_count, cache.query_time]
    end

    def track_memcached?
      return @track_memcached if defined?(@track_memcached)
      @track_memcached = defined?(Memcached::Rails) && Memcached::Rails.respond_to?(:query_count)
    end

    # Memcached stats for current request.
    def memcached_stats
      memcached = Memcached::Rails
      [memcached.query_count, memcached.query_time]
    end

    def track_glb?
      @glb_via.present?
    end

    def track_aqueduct_stats?
      @track_aqueduct_stats
    end

    def track_collectors?
      @track_collectors
    end

    def track_markdown?
      @track_markdown
    end

    def markdown_stats
      [
        GitHub::Goomba::WarpPipeStats.call_count,
        GitHub::Goomba::WarpPipeStats.call_time,
      ]
    end

    # Converts a header like:
    #   hostname=glb-proxy12-cp1-prd.iad.github.net t=2; hostname=github-fe-e841886.sdc42-sea.github.net
    #
    # into an array of hashes like this:
    #   [
    #     {"hostname" => "glb-proxy12-cp1-prd.iad.github.net", "t" => "2"},
    #     {"hostname" => "github-fe-e841886.sdc42-sea.github.net"},
    #   ]
    #
    # Returns Array of Hashes.
    def glb_via
      return [] unless track_glb?
      hops = @glb_via.split(",".freeze)
      hops.map do |hop|
        key_value_pairs = hop.split(" ".freeze)
        key_value_pairs.inject({}) do |hash, key_value_pair|
          key, value = key_value_pair.split("=".freeze, 2)
          hash[key.strip] = value.strip
          hash
        end
      end
    end

    # AR stats for the current request.
    #
    # Returns an Array of
    #   obj_count  - Number of AR objects initialized
    #   obj_types  - Hash of ModelName:count entries
    #   cache_hits - Number of AR query cache hits
    def activerecord_stats
      ar = ActiveRecord::Base
      [
        GitHub::MysqlInstrumenter.active_record_obj_count,
        GitHub::MysqlInstrumenter.active_record_obj_types,
        GitHub::MysqlInstrumenter.cached_query_count,
      ]
    end

    def track_render?
      return @track_render if defined?(@track_render)
      @track_render = defined?(ActionView::Template) && ActionView::Template.respond_to?(:template_trace)
    end

    # Public: Provides the names of features that have been queried to
    # determine if they are `enabled?`
    #
    # Returns a Hash in the form of { String => Boolean }
    def tested_features
      return unless track_tested_features?
      FlipperSubscriber.tested_features
    end

    # Public: provides the names of current enabled features
    def enabled_features
      return unless track_tested_features?
      tested_features.select { |_feature, enabled| enabled }.map(&:first)
    end

    def track_tested_features?
      return @track_tested_features if defined?(@track_tested_features)
      @track_tested_features = defined?(FlipperSubscriber) && FlipperSubscriber.respond_to?(:tested_features)
    end

    # Template rendering stats for the current request.
    #
    # Returns a Rack::Bug::TemplatesPanel::Trace
    def render_stats
      ActionView::Template.template_trace
    end

    # Body wrapper. Yields the body's bytesize to the block when body is
    # closed. This is used to signal when a response is fully finished
    # processing.
    class Body
      def initialize(body, &block)
        @body = body
        @block = block
        @bytesize = 0
      end

      def each
        @body.each do |content|
          @bytesize += content.bytesize
          yield content
        end
      end

      def close
        @body.close if @body.respond_to?(:close)
        @block.call(@bytesize)
        nil
      end
    end

    # Provide GLB with additional log line data relating to the rails view of the world (what and how long).
    # This will be used to allow GLB to emit "overhead" measurements that exclude unicorn time.
    # See: https://github.com/github/fast/discussions/2#discussioncomment-145438
    def inject_glb_response_headers(headers, env)
      return headers if GitHub.enterprise?

      glb_log_data = []

      # We need to be able to distinguish easily between browser, ajax, etc requests
      # for the purpose of understanding timing consistently. We use the 'datadog'
      # variant because our end goal is to emit datadog metrics at the GLB layer that
      # match up tag-wise with the Rails-level DD metrics.
      glb_log_data << ["request_category", request_category_datadog(env)]

      # Likewise for HTTP methods. For example, Rails will interpret:
      #
      # - a `POST` with `_method:put` as a `PUT`; or:
      # - a `POST` with `_method:delete` as a `DELETE; etc...
      #
      # ie. https://github.com/rails/rails/blob/db6159ce62b393d4422d4890f26b53c66db5c4f9/actionpack/test/dispatch/request_test.rb#L796-L804
      #
      # So, we want `glb.rails.response` to include `rails_method:put` (or
      # `rails_method:delete` etc) so that we can distinguish between the
      # different types of requests that GLB would otherwise conflate together
      # because it sees them as having `method:post`).
      glb_log_data << ["method", env["REQUEST_METHOD"]&.downcase]

      # We want to be able to tag by controller+action, the same as for metrics (since we'll be
      # creating metrics out of these log lines).
      glb_log_data << [GitHub::TaggingHelper::CONTROLLER_TAG, GitHub::TaggingHelper.controller(env)]
      glb_log_data << [GitHub::TaggingHelper::ACTION_TAG, GitHub::TaggingHelper.action(env)]
      glb_log_data << [GitHub::TaggingHelper::CATALOG_SERVICE_TAG, GitHub::TaggingHelper.catalog_service(env)]
      is_react = GitHub::TaggingHelper.is_react?(env)
      glb_log_data << [GitHub::TaggingHelper::IS_REACT_TAG, is_react] if is_react

      glb_log_data << ["application_role", GitHub.role]
      glb_log_data << ["deployed_to", GitHub.deployed_to]
      glb_log_data << ["kube_namespace", GitHub.kubernetes_namespace]
      glb_log_data.concat(GitHub.user_specified_tags.map { |tag| tag.split(":") })

      # Matches up with the metric "request.queued.time"
      if queue_time = env[GitHub::TaggingHelper::REQ_WAIT_TIME]
        queue_ms = queue_time * 1_000
        glb_log_data << ["request_queued_time", queue_ms.to_i]
      end

      # Matches up with the metric "request.dist.time"
      if cpu_timing = env[GitHub::TaggingHelper::REQ_CPU_TIMES]
        _, _, real_time = cpu_timing
        real_ms = real_time * 1_000
        glb_log_data << ["request_time", real_ms.to_i]
      end

      # As per GLB log standards, non-GLB metrics are emitted with prefixes for the component that adds them.
      # We'll use "rails_" since it's the general term for anything at this layer and matches the Splunk index.
      headers["X-GLB-Log-Append"] = glb_log_data.map { |name, value| "rails_#{name}=#{value}" }.join(" ")
      headers
    rescue => boom # rubocop:todo Lint/GenericRescue
      warn "ProcessUtilization#inject_glb_response_headers failed: #{boom.inspect}\n#{boom.backtrace.to_a.join("\n")}"
      headers
    end

    ENV_KEY = "github.rack.process_utilization"

    # Rack entry point.
    def call(env)
      env[ENV_KEY] = self

      # Skip stats and procline on warmup requests in unicorn master
      return @app.call(env) if GitHub.unicorn_master_pid == Process.pid

      reset_stats

      @total_requests += 1
      first_request if @total_requests == 1

      env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY]           = nil
      env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY_DATADOG]   = nil
      env[GitHub::TaggingHelper::PROCESS_REQUEST_PJAX]               = nil
      env[GitHub::TaggingHelper::PROCESS_REQUEST_LOGGED_IN]          = nil
      env[GitHub::TaggingHelper::PROCESS_REQUEST_START]              = @start
      env["process.total_requests"]                                  = total_requests
      env[GitHub::TaggingHelper::STATSD_SAMPLE_RATE]                 = DEFAULT_STATSD_SAMPLE_RATE
      env[GitHub::TaggingHelper::ALLOY_WAIT_TIME]                    = 0
      GitHub.unicorn_worker_request_count                            = total_requests

      @glb_via = env["HTTP_X_GLB_VIA"]

      status, headers, body = @app.call(env)
      if track_cpu? && @cputime
        # Save this CPU time once, and allow it to be re-used multiple times by stats (keeping the same value)
        env[GitHub::TaggingHelper::REQ_CPU_TIMES] = cpu_stats
      end
      body = Body.new(body) do |response_size|
        record_request(response_size, status, env)
      end

      headers = inject_glb_response_headers(headers, env)

      [status, headers, body]
    end
  end
end
