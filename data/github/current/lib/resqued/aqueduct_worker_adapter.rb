# typed: true
# frozen_string_literal: true

require "aqueduct"

module Resqued
  # A worker class adapter for resqued that supports the same interface as
  # a `Resque::Worker` but delegates to an aqueduct worker.
  class AqueductWorkerAdapter
    attr_reader :worker, :queues

    def initialize(*queues, backend: nil, prioritize_by: nil, queue_subset_selector: nil)
      @queues = queues
        .map { |queue_name| GitHub::Aqueduct::Job.aqueduct_queue_name(queue_name) }
        .uniq
      @worker = ::Aqueduct::Worker::Worker.new(
        backend: set_github_component { backend || GitHub.aqueduct_worker_backend(prioritize_by: prioritize_by, queue_subset_selector: queue_subset_selector) },
        queues: @queues,
        logger: Rails.logger,
      )

      # Store a reference to the current worker in a global variable, so that
      # jobs can use it to check the shutdown status of the worker.
      $aqueduct_worker = @worker
    end

    def set_github_component
      original_component = GitHub.component
      GitHub.component = GitHub::Aqueduct::COMPONENT
      yield
    ensure
      GitHub.component = original_component
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
      @worker.work(interval)
    end
  end
end
