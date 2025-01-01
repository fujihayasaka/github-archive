# typed: true
# frozen_string_literal: true

module ActiveJob
  module QueueAdapters
    class JobRouter
      # Sends jobs to the aqueduct gateway.
      AQUEDUCT_GATEWAY_PATH = :aqueduct_gateway

      # Sends jobs to the primary aqueduct cluster.
      AQUEDUCT_PRIMARY_PATH = :aqueduct_primary

      # Sends jobs to the secondary aqueduct cluster.
      AQUEDUCT_SECONDARY_PATH = :aqueduct_secondary

      # Sends jobs to a hydro topic synchronously. Used as a failover when other routes are down.
      # A hydro consumer consumes jobs from the topic and reroutes them to real queue backends.
      HYDRO_SYNC_PATH = :hydro_sync

      # Sends jobs to a hydro topic asynchronously. Used as a failover when a request has enqueued
      # too many jobs in the foreground. A hydro consumer consumes jobs from the topic and reroutes
      # them to real queue backends.
      HYDRO_ASYNC_PATH = :hydro_async

      # The maximum amount of time in milliseconds that a path can spend enqueueing before we
      # remove the path for the route. Only affects enqueues from requests and resets on each request.
      TIME_BUDGETS = {
        AQUEDUCT_GATEWAY_PATH => 1000,
        AQUEDUCT_PRIMARY_PATH => 1000,
        AQUEDUCT_SECONDARY_PATH => 1000,
        HYDRO_SYNC_PATH => 1000,
      }

      # A list of idempotent jobs that we can fan out to across multiple routes.
      FANOUT = []

      # A list of job that should only be enqueued via the async enqueue route.
      ASYNC_ONLY = [
        "AqueductRelayTestJob"
      ]

      # A Route specifies the preferred enqueue path, a list of prioritized failover paths to be
      # used if the preferred path fails, and an optional list of fanout paths if the job should
      # enqueue to multiple paths.
      class Route
        attr_reader :preferred_path, :failover_paths, :fanout_paths

        def initialize(preferred_path:, failover_paths: [], fanout_paths: [])
          @preferred_path = preferred_path
          @failover_paths = Array.wrap(failover_paths)
          @fanout_paths = Array.wrap(fanout_paths)
        end
      end

      # Public: The maximum number of jobs of a given class that can be enqueued in the foreground.
      # Once we hit this limit, the route switches to async enqueues for the duration of the
      # request. We default to a limit of 50 in an effort to keep total time spent enqueueing under
      # 1000 ms.
      #
      # Returns a boolean.
      def self.bulk_enqueue_limit
        50
      end

      # Public: Build an enqueue route for a job.
      #
      # Returns a Route.
      def self.route_for(job)
        return enterprise_route(job) if GitHub.enterprise?

        # Have we already enqueued too many of these jobs in the foreground?
        if at_bulk_enqueue_limit?(job) && job.class.allow_async_enqueues?
          return async_enqueue_route
        end

        if ASYNC_ONLY.include?(job.class.name)
          return async_only_enqueue_route
        end

        paths = []

        unless time_budget_exceeded?(AQUEDUCT_PRIMARY_PATH)
          paths << AQUEDUCT_PRIMARY_PATH
        end

        unless time_budget_exceeded?(AQUEDUCT_SECONDARY_PATH)
          paths << AQUEDUCT_SECONDARY_PATH
        end

        if prefer_aqueduct_secondary?
          paths = paths.reverse
        end

        if include_gateway? && !time_budget_exceeded?(AQUEDUCT_GATEWAY_PATH)
          paths = [AQUEDUCT_GATEWAY_PATH] + paths
        end

        if time_budget_exceeded?(HYDRO_SYNC_PATH)
          paths << HYDRO_ASYNC_PATH if job.class.allow_async_enqueues?
          paths << HYDRO_SYNC_PATH
        else
          paths << HYDRO_SYNC_PATH
          paths << HYDRO_ASYNC_PATH if job.class.allow_async_enqueues?
        end

        route = {
          preferred_path: paths.first,
          failover_paths: paths[1..-1],
        }

        if fanout?(job)
          route[:fanout_paths] = [
            HYDRO_SYNC_PATH,
            AQUEDUCT_SECONDARY_PATH
          ]
        end

        Route.new(**route)
      end

      # Public: Build an enqueue route for a scheduled job.
      #
      # Returns a Route.
      def self.route_for_scheduled_job(job)
        return enterprise_route(job) if GitHub.enterprise?

        paths = [AQUEDUCT_PRIMARY_PATH, AQUEDUCT_SECONDARY_PATH]

        if prefer_aqueduct_secondary?
          paths = paths.reverse
        end

        if include_gateway?
          paths = [AQUEDUCT_GATEWAY_PATH] + paths
        end

        paths << HYDRO_SYNC_PATH << HYDRO_ASYNC_PATH

        route = {
          preferred_path: paths.first,
          failover_paths: paths[1..-1],
        }

        Route.new(**route)
      end

      # Internal: Build an async enqueue route.
      #
      # Returns a Route.
      def self.async_enqueue_route
        Route.new(
          preferred_path: HYDRO_ASYNC_PATH,
          failover_paths: [
            AQUEDUCT_PRIMARY_PATH
          ],
        )
      end

      # Internal: Build an async enqueue route with no fallback.
      #
      # Returns a Route.
      def self.async_only_enqueue_route
        Route.new(
          preferred_path: HYDRO_ASYNC_PATH
        )
      end

      # Internal: Build a route for jobs enqueued in enterprise
      #
      # Returns a Route.
      def self.enterprise_route(job)
        Route.new(
          preferred_path: AQUEDUCT_PRIMARY_PATH,
        )
      end

      def self.at_bulk_enqueue_limit?(job)
        # We don't limit bulk enqueues outside requests.
        return unless GitHub.foreground?

        GitHub::JobStats.enqueue_time_ms >= 1000 &&
          GitHub::JobStats.enqueue_count(job_class: job.class) >= bulk_enqueue_limit
      end

      def self.time_budget_exceeded?(path)
        # We only worry about time budgeting during requests. It's okay if
        # background jobs exceed the budget by enqueueing many jobs.
        return unless GitHub.foreground?

        budget = TIME_BUDGETS[path] || return
        if GitHub::JobStats.enqueue_time_per_backend_ms[path] >= budget
          GitHub.dogstats.increment("job_router.time_budget_exceeded", tags: ["path:#{path}"])
          true
        end
      end

      def self.include_gateway?
        GitHub.flipper["aqueduct_enqueue_to_gateway"].enabled?
      end

      def self.prefer_aqueduct_secondary?
        GitHub.flipper["aqueduct_enqueue_to_secondary"].enabled?
      end

      # Internal: Some jobs are idempotent and can fan out to multiple routes.
      def self.fanout?(job)
        FANOUT.include?(job.class.to_s)
      end
    end
  end
end
