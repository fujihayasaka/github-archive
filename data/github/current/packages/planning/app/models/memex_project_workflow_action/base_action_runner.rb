# typed: false
# frozen_string_literal: true

class MemexProjectWorkflowAction::BaseActionRunner
  include MemexHydroProjectAutomation::Instrumentation::PipedActions

  ACTION_TYPE = :none
  BATCH_SIZE = 10

  def self.run(**kwargs)
    new(**kwargs).run
  end

  def initialize(action:, input:, actor:, trigger_type: nil, manual_run: false, tags: [], content_types: nil)
    raise ArgumentError, "action must be of type :#{self.class::ACTION_TYPE}" unless action.action_type.to_sym == self.class::ACTION_TYPE

    @action = action
    @input = input
    @actor = actor
    @manual_run = manual_run
    @tags = tags
    @trigger_type = trigger_type
    @content_types = content_types
  end

  def run
    raise NotImplementedError
  end

  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end

  def log_duration(&block)
    log_trigger_and_duration(
      type: "action",
      trigger_metric: METRIC_TRIGGERED,
      duration_metric: METRIC_DURATION,
      &block)
  end
end
