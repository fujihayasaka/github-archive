# frozen_string_literal: true

require "aqueduct"
require_relative "aqueduct_worker"

module Aqueduct
  # A worker class adapter for resqued that supports the same interface as
  # a `Resque::Worker` but delegates to an aqueduct worker.
  class ResquedWorkerAdapter
    attr_reader :worker, :queues

    def initialize(*queues, backend: nil)
      @queues = queues
      @worker = DependencyGraph::Aqueduct::Worker.new(queues: queues)

      # Store a reference to the current worker in a global variable, so that
      # jobs can use it to check the shutdown status of the worker.
      $aqueduct_worker = @worker
    end

    # Resqued configs set this cant_fork value via the configuration API.
    def cant_fork=(boolean)
      ::Aqueduct::Worker.configure do |config|
        config.fork_per_job = !boolean
      end
    end

    # Resqued configs set this graceful_term value via the `after_fork` configuration API.
    def graceful_term=(boolean)
      ::Aqueduct::Worker.configure do |config|
        config.graceful_term = boolean
      end
    end

    def work(interval)
      @worker.start(interval: interval)
    end
  end
end
