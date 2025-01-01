# typed: true
# frozen_string_literal: true

class GhesActionsJobExecution < ApplicationRecord::Domain::GhesActions
  include Instrumentation::Model
  include GitHub::Validations

  self.table_name = :ghes_actions_job_executions

  alias_attribute :check_run_id, :job_check_run_id
  alias_attribute :check_suite_id, :job_check_suite_id
  alias_attribute :start_time, :started_at
  alias_attribute :end_time, :finished_at

  attribute :event_id, :uuid_type

  scope :created_between, -> (lower_bound, upper_bound) { where("created_at >= ? AND created_at <= ?", lower_bound, upper_bound) }
end
