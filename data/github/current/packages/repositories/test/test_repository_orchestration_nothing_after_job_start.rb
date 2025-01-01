# typed: strict
# frozen_string_literal: true

class TestRepositoryOrchestrationNothingAfterJobStart < RepositoryOrchestration
  step :step_zero do
    data[:step_zero_count] = (data[:step_zero_count] || 0) + 1
  end

  job_start
end
