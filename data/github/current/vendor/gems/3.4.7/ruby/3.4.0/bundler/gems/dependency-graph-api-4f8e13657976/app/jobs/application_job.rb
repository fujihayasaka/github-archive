require "securerandom"
require_relative "../../lib/logging"

class ApplicationJob < ActiveJob::Base
  def all_stats_tags
    %W(class:#{self.class.name.underscore} queue:#{queue_name}).concat(stats_tags).compact
  end

  # Override this in your job if you'd like to include custom tags
  def stats_tags
    []
  end

  # Returns a hash of options to be merged into the Aqueduct queue_job call
  # Subclasses can override this to provide custom queue settings
  def self.queue_options
    {}
  end

  around_enqueue do |job, block|
    block.call
  rescue => e
    instrument_enqueue_error!(e) unless handler_for_rescue(e)
    raise
  end

  around_perform do |job, block|
    DependencyGraph.logger.log_and_failbot_context({ "gh.dependency_graph.job_instance_id" => SecureRandom.uuid }) do
      if executions > 1
        DependencyGraph.logger.info("Retrying job", "retries" => executions - 1)
      end
      block.call
    end
  rescue => e
    instrument_error!(e) unless handler_for_rescue(e)
    raise
  end

  private

  def instrument_job(name, error: nil, on: nil)
    ActiveSupport::Notifications.instrument("#{name}.active_job", error: error, on: on, job: self) do |*args|
      yield(*args) if block_given?
    end
  end

  def instrument_enqueue_error!(error)
    instrument_job("error", error: error, on: :enqueue) do |payload|
      Failbot.report(error,
        "gh.aqueduct.queue.name" => queue_name,
        "gh.aqueduct.job.name" => payload[:job].class.to_s
      )
      raise # allow ActiveSupport::Notifications to add exception to payload
    end
  end

  def instrument_error!(error)
    instrument_job("error", error: error, on: :perform) do |payload|
      Failbot.report(error,
        "gh.aqueduct.queue.name" => queue_name,
        "gh.aqueduct.job.name" => payload[:job].class.to_s
      )
      raise # allow ActiveSupport::Notifications to add exception to payload
    end
  end
end
