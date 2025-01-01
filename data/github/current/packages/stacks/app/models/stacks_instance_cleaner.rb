# typed: true
# frozen_string_literal: true

class StacksInstanceCleaner
  def self.cleanup_dependancies(stacks_instance)
    unless stacks_instance.completed?
      push_instance_metrics "status", __callee__, "error"
      raise Errors::StacksInstanceCleanupError, "Cannot cleanup dependancies of an incomplete instance"
    end

    stacks_instance.transaction do
      stacks_instance.stacks_plan.delete_all
      stacks_instance.stacks_step.delete_all
      stacks_instance.stacks_flow.delete_all
      stacks_instance.stacks_status.delete_all
    end
    rescue StandardError => e # rubocop:todo Lint/RescueException
      raise e if e.is_a?(Errors::StacksInstanceCleanupError)
      push_instance_metrics "status", __callee__, "error"
  end

  private_class_method def self.push_instance_metrics(metric_name, operation, status)
    Metrics.push_metric Metrics::INCREMENT, Component::INSTANCE, operation, metric_name, tags: ["action:#{status}"]
  end
end
