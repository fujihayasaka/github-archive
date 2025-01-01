# typed: false
# frozen_string_literal: true

module StacksSteps
  class Step < ApplicationRecord::Domain::Stacks # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
    BATCH_SIZE = 100

    belongs_to :plan, class_name: "StacksPlan"
    belongs_to :flow, class_name: "StacksFlow"
    belongs_to :instance, class_name: "StacksInstance"

    @@max_retry = 0
    @@non_retryable_errors = Set.new
    attr_accessor :status
    @status = :initialized
    @actor = nil

    def self.table_name_prefix
      "stacks_"
    end

    def weight
      @weight ||= StacksSteps::WeightMap::TEN_SECOND
    end

    def self.insert_bulk_step_records(records)
      ActiveRecord::Base.connected_to(role: :writing) do
        records.each_slice(BATCH_SIZE) do |slice|
          throttle do
            insert_all(slice)
          end
        end
      end
    end

    def self.fetch_steps_for_flow(instance_id, flow_id)
      steps = self.where(instance_id: instance_id).where(flow_id: flow_id)
      steps = steps.sort_by { |step| step[:id] }
      steps
    end

    def self.fetch_steps_for_plan(instance_id)
      self.where(instance_id: instance_id)
    end

    def try_run(repo:, actor:)
      if @@max_retry < 0
        raise "Invalid max_retry."
      end
      @status = :running
      attempts = 0
      while @status == :running do
        begin
          update_step_status(self.instance_id, self.plan_id, self.id, StacksStatus.statuses[:in_progress])
          run(repo: repo, actor: actor)
          @status = :success
          update_step_status(self.instance_id, self.plan_id, self.id, StacksStatus.statuses[:success], "The step successfully executed")
        rescue StandardError => e # rubocop:todo Lint/RescueException
          if @@non_retryable_errors.include?(e.class)
            @status = :failure
            update_step_status(self.instance_id, self.plan_id, self.id, StacksStatus.statuses[:failed], e.message)
            raise e
          elsif  attempts < @@max_retry
            @status = :running
            attempts += 1
          else
            @status = :failure
            update_step_status(self.instance_id, self.plan_id, self.id, StacksStatus.statuses[:failed], e.message)
            raise e
          end
        end
      end
    end

    def get_step_metadata
      data = {
        "id" => self.id,
        "type" => self.type
      }

      data
    end

    private

    # group steps to one of the following:
    # StepGroup::REPO_CLONING, StepGroup::CONFIG, StepGroup::WORKFLOW_RUN
    def get_step_group
      raise Errors::UnknownStepGroupError.new("Step group not implemented.")
    end

    def run(repo:, actor:)
      raise Errors::StepError.new("Step run not implemented.")
    end

    def cleanup(repo:, actor:)
      raise Errors::StepError.new("Step cleanup not implemented.")
    end

    def update_step_status(instance_id, plan_id, step_id, step_status, message = nil)
      StacksStatus.where(instance_id: instance_id)
               .where(plan_id: plan_id)
               .where(entity_type: StacksStatus.entity_types[:step])
               .where(entity_id: step_id)
               .update({ status: step_status, message: message })

      update_step_start_and_end_times
      self.instance.update_status
    end

    def update_step_start_and_end_times
      self.start_time = start_time.present? ? self.start_time : DateTime.now
      self.end_time = compute_end_time
      save!
    end

    def compute_end_time
      if completed?
        return end_time if end_time.present?
        DateTime.now
      end
    end

    def success?
      @status == :success
    end

    def failed?
      @status == :failure
    end

    def completed?
      success? || failed?
    end
  end
end
