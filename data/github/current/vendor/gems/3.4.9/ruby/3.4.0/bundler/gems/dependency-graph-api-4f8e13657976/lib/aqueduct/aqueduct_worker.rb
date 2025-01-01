# frozen_string_literal: true

require_relative "aqueduct_adapter"

# Autoloader hack: we use the PackageReleaseSerializer class here for some jobs, and we need it loaded
# for Aqueduct to be able to use it
require "./etl/packages/package_release"

# This file was inspired by (but is an incredibly simplified version) of
# https://github.com/github/meuse/blob/main/script/aqueduct-worker
module DependencyGraph
  module Aqueduct
    class Worker
      def initialize(client: DependencyGraph.aqueduct.client, queues: nil)
        # We take a much more naive approach (at least for now) than what Meuse does for their workers -
        # we're just using the stock Aqueduct worker implementation.
        @worker = ::Aqueduct::Worker::Worker.new(
          backend: ::Aqueduct::Worker::AqueductBackend.new(client: client),
          queues: queues || DependencyGraph.aqueduct.queues,
          # Works around a quirk of the Aqueduct client library:
          # https://github.com/github/github-telemetry-ruby/issues/505#issuecomment-1614138279
          # https://github.com/github/aqueduct-client-ruby/issues/94
          # Using a standard logger here instead of Semantic Logger will prevent
          # useless exception reports to Sentry when the pods are killed.
          # Note that this is only for the Aqueduct _internal_ logger.
          # Anything we use DependencyGraph.logger for in the jobs themselves does not use this.
          logger: ::Logger.new(STDERR)
        )
      end

      def start(interval: nil)
        DependencyGraph.logger.info("starting aqueduct worker, listening for queues", "gh.aqueduct.queue.names" => DependencyGraph.aqueduct.queues)
        if interval
          @worker.work(interval)
        else
          @worker.work
        end
      ensure
        OpenTelemetry.tracer_provider.force_flush
        DependencyGraph.logger.error("exit with last known error",
          $ERROR_INFO
          ) if $ERROR_INFO.present?
      end

      def stop
        @worker.shutdown
      end
    end
  end
end
