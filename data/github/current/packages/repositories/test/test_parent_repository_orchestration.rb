# typed: false
# frozen_string_literal: true

# this is a test orchestration for testing the orchestration engine
module TestParentOrchestrationModule
  extend ActiveSupport::Concern

  included do
    step :start_step do
      data[:step_one_count] = (data[:step_one_count] || 0) + 1
    end

    job_start

    step :queue_children, max_attempts: 1 do
      self.data[:step_two_count] = (data[:step_two_count] || 0) + 1
      self.data[:repo_ids] ||= []
      self.data[:child_ids] ||= []

      count = 0
      self.data[:repo_ids].each do |repo_id|
        child_data = nil
        if count == 0
          if self.data[:child_should_raise_in_job]
            child_data = { step_four_should_raise: true }
          elsif self.data[:child_should_raise_in_start]
            child_data = { step_two_should_raise: true }
          elsif self.data[:child_should_crash_in_job]
            child_data = { step_four_should_crash: true }
          end
        end

        repo = Repository.find(repo_id)
        orchestration = TestRepositoryOrchestration.create(repository: repo, data: child_data)
        block_on_orchestration(orchestration)
        self.data[:child_ids] << orchestration.id
        count = count + 1
      end
    end

    step :finish_step do
      data[:step_three_count] = (data[:step_three_count] || 0) + 1
    end
  end
end

class TestParentRepositoryOrchestration < RepositoryOrchestration
  include TestParentOrchestrationModule
end
