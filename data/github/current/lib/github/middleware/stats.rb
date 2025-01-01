# typed: true
# frozen_string_literal: true

require "github/config/graphite"
require "github/sorbet/runtime"
require "github/tagging_helper"
require "github/datadog_tags_cache"
require "rack/process_utilization"
require "github/middleware/stats/tracker"

# READ ME!
#
# Are you looking to add a new metric as a part of the stats middleware?
# Then don't add new metrics to this file and instead create a new file
# in the lib/github/middleware/stats/tracker directory. The new file should
# contain a class which implements the Stats::Tracker interface. For an example,
# see lib/github/middleware/stats/tracker/request_timing.rb.

module GitHub
  module Middleware
    Dir[Rails.root + "lib/github/middleware/stats/tracker/*.rb"].each { |r| require r }

    class Stats
      def initialize(app)
        @app = app
      end

      def call(env)
        @real_start            = realtime
        @start_time            = Time.now
        @cpu_start             = cputime
        @cpu_thread_start      = cpu_thread_time
        env[TaggingHelper::REQ_WAIT_TIME] = request_wait_time(env)
        env[TaggingHelper::GLB_WAIT_TIME] = glb_wait_time(env)

        @status, _headers, _body = @app.call(env)
      ensure
        begin
          collect_stats(env)
        rescue => error # rubocop:todo Lint/RescueException
          Failbot.report!(error) rescue nil
        end
      end

      def emit_timing_metrics?
        return @emit_timing_metrics if defined?(@emit_timing_metric)
        @emit_timing_metrics = rand < GitHub.stats_middleware_timing_metrics_sample_rate
      end

      def collect_stats(env)
        # Skip stats on warmup requests in unicorn master
        return if GitHub.unicorn_master_pid == Process.pid

        real_end = stats_start = realtime
        real_ms = (real_end - @real_start) * 1_000.0
        cpu_ms = (cputime - @cpu_start) * 1_000.0
        cpu_thread_ms = (cpu_thread_time - @cpu_thread_start) * 1_000.0
        idle_ms = real_ms - cpu_ms

        controller = TaggingHelper.controller(env)

        stats = {
          stats_start:                   stats_start,
          real_ms:                       real_ms,
          cpu_ms:                        cpu_ms,
          cpu_thread_ms:                 cpu_thread_ms,
          idle_ms:                       idle_ms,
          response_status:               @status || TaggingHelper::UNKNOWN,
          status_range:                  TaggingHelper.status_range(@status || TaggingHelper::UNKNOWN),
          request_category:              TaggingHelper.category(env),
          request_method:                TaggingHelper.request_method(env),
          pjax:                          TaggingHelper.pjax(env),
          logged_in:                     TaggingHelper.logged_in(env),
          profile_type:                  TaggingHelper.profile_type(env),
          controller:                    controller,
          action:                        TaggingHelper.action(env),
          graphql_api_request:           TaggingHelper.graphql_api_request?(controller),
          graphql_operation_type:        TaggingHelper.graphql_operation_type(env),
          catalog_service:               TaggingHelper.catalog_service(env),
          internal_api:                  TaggingHelper.internal_api?(env),
          command_palette_provider_name: TaggingHelper.command_palette_provider_name(env),
          codespaces_automated_testing:  TaggingHelper.codespaces_automated_testing?(env),
          alloy_calls:                   TaggingHelper.alloy_calls(env),
          repo_advisory_source_type:     TaggingHelper.repo_advisory_source_type(env),
          is_react:                      TaggingHelper.is_react?(env),
          is_staff:                      TaggingHelper.is_staff?(env)
        }

        tags_cache = DatadogTagsCache.new({
          TaggingHelper::STATUS_TAG           => stats[:response_status],
          TaggingHelper::STATUS_RANGE_TAG     => stats[:status_range],
          TaggingHelper::METHOD_TAG           => stats[:request_method],
          TaggingHelper::CATEGORY_TAG         => stats[:request_category],
          TaggingHelper::CATALOG_SERVICE_TAG  => stats[:catalog_service],
          TaggingHelper::CONTROLLER_TAG       => stats[:controller],
          TaggingHelper::ACTION_TAG           => stats[:action],
          TaggingHelper::POD_NAME_TAG         => GitHub.kubernetes_pod_name,
          TaggingHelper::GRAPHQL_API_TAG      => stats[:graphql_api_request],
          TaggingHelper::INTERNAL_API_TAG     => stats[:internal_api],
          TaggingHelper::PROFILE_TYPE         => stats[:profile_type],
          TaggingHelper::LOGGED_IN_TAG        => stats[:logged_in],
          TaggingHelper::COMMAND_PALETTE_PROVIDER_NAME_TAG => stats[:command_palette_provider_name],
          TaggingHelper::REPO_ADVISORY_SOURCE_TYPE_TAG => stats[:repo_advisory_source_type],
          TaggingHelper::IS_REACT_TAG         => stats[:is_react],
          TaggingHelper::STAFF_TAG            => stats[:is_staff]
        })

        trackers_total_time = 0
        Tracker.constants.each do |const|
          if emit_timing_metrics?
            tracker_start_time = realtime
            const_obj = Tracker.const_get(const)
            next unless const_obj.is_a?(Tracker)
            T.cast(const_obj, Tracker).track(GitHub.dogstats, env, stats, tags_cache)
            tracker_duration = (realtime - tracker_start_time) * 1_000_000 # microseconds
            GitHub.dogstats.distribution("request.dist.stats_tracker_time", tracker_duration, tags: ["tracker:#{const}"])
            trackers_total_time += tracker_duration
          else
            const_obj = Tracker.const_get(const)
            next unless const_obj.is_a?(Tracker)
            T.cast(const_obj, Tracker).track(GitHub.dogstats, env, stats, tags_cache)
          end
        end

        stats_time = (realtime - stats[:stats_start]) * 1_000_000.0 # microseconds
        GitHub.dogstats.distribution("request.dist.stats_time", stats_time)
        GitHub.dogstats.distribution("request.dist.stats_tracker_time", stats_time - trackers_total_time, tags: ["tracker:untracked"]) if emit_timing_metrics?
      end

      private

      def realtime
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def cputime
        Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      end

      def cpu_thread_time
        Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
      end

      # The time the request spent waiting to be serviced by a unicorn
      def request_wait_time(env)
        return nil unless env["HTTP_X_NGINX_REQUEST_START"]

        # Nginx constructs the timestamp using the macro "t=${msec}000" which
        # produces a header in format t=seconds.microseconds, which is the same
        # as the to_f representation of a Ruby Time.
        nginx_start = env["HTTP_X_NGINX_REQUEST_START"][2..].to_f
        @start_time.to_f - nginx_start if nginx_start > Float::MIN
      end

      # The time since the request arrived at the GLB edge
      def glb_wait_time(env)
        return nil unless env["HTTP_X_REQUEST_START"]

        # HAProxy provides the X-Request-Start header in the format
        # t=microseconds since epoch, which needs to be scaled to seconds
        # to match the to_f representation of @starttime
        glb_start = env["HTTP_X_REQUEST_START"][2..].to_f
        @start_time.to_f - (glb_start / 1_000_000) if glb_start > Float::MIN
      end
    end
  end
end
