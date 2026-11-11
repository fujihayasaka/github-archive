# typed: false
# frozen_string_literal: true

class StatusGroup
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Serializers::JSON
  include StatusHelper
  include StacksSteps

  attr_accessor :name, :steps_metadata, :status, :start_time, :end_time, :messages, :total_jobs
  def initialize(args = {})
    @name = args[:name]
    @steps_metadata = args[:steps_metadata]
    @status = args[:status]
    self.start_time = args[:start_time]&.to_datetime
    self.end_time = args[:end_time]&.to_datetime
    @messages = args[:messages]
    @total_jobs = args[:total_jobs]
  end

  def self.from_json(value)
    case value
    when String
      new.from_json(value)
    when Hash, nil
      new(value)
    end
  end

  def attributes
    instance_values
  end

  def ==(other)
    name == other.name &&
    status == other.status
  end

  def duration
    return 0 unless completed?
    raw_seconds = ((end_time.to_datetime - start_time.to_datetime) * 24 * 60 * 60).to_i
    precise_duration(raw_seconds)
  end

  def repo_cloning?
    name == StepGroup.repo_cloning.name
  end

  def repo_config?
    name == StepGroup.repo_config.name
  end

  def workflow_run?
    name == StepGroup.workflow_run.name
  end

  def cleanup?
    name == StepGroup.stack_cleanup.name
  end

  def success?
    status == StacksStatus.statuses.key(StacksStatus.statuses[:success])
  end

  def failed?
    status == StacksStatus.statuses.key(StacksStatus.statuses[:failed])
  end

  def completed?
    success? || failed?
  end

  def in_progress?
    status == StacksStatus.statuses.key(StacksStatus.statuses[:in_progress])
  end

  def not_started?
    status == StacksStatus.statuses.key(StacksStatus.statuses[:not_started])
  end

  def workflow_run_successful?
    workflow_run? && success?
  end
end
