# typed: true
# frozen_string_literal: true

class StacksInstanceStatus
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Serializers::JSON
  attr_accessor :instance_id, :plan_id, :step, :status, :duration, :step_statuses, :failed_step_group

  NONE = "none"

  def initialize(args = {})
    self.instance_id = args[:instance_id]
    self.plan_id = args[:plan_id]
    self.status = args[:status]
    self.duration = compute_instance_run_duration(args[:statuses]) if args[:statuses]
    self.step_statuses = args[:statuses]
    self.failed_step_group = get_failed_step_group(args[:failed_step_group])
  end

  def self.from_json(value)
    case value
    when String
      status = new.from_json(value)
      status.step_statuses = status.step_statuses&.map { |step| StatusGroup.from_json(step.to_json) }
      status
    when Hash, nil
      new(value)
    end
  end

  def attributes
    instance_values
  end

  def ==(other)
    instance_id == other.instance_id &&
    plan_id == other.plan_id &&
    status == other.status &&
    step_statuses.length == other.step_statuses.length &&
    step_statuses.zip(other.step_statuses).all? { |a, b| a == b }
  end

  def get_failed_step_group(group)
    return NONE if success?
    group
  end

  def repo_clone_successful?
    failed_step_group != StepGroup.repo_cloning.name
  end

  def ran_successfully?
    failed_step_group == NONE
  end

  def success?
    status == "success"
  end

  def in_progress?
    status == "in_progress"
  end

  def failed?
    status == "failed"
  end

  def completed?
    success? || failed?
  end

  def not_started?
    status == "not_started"
  end

  private

  def compute_instance_run_duration(statuses)
    return 0 unless statuses.present? || completed?
    start_time = statuses.map { |step| step.start_time&.to_datetime }.compact.min
    end_time   = statuses.map { |step| step.end_time&.to_datetime }.compact.max
    return 0 unless start_time && end_time
    ((end_time - start_time) * 24 * 60 * 60).to_i #return the difference in seconds
  end
end
