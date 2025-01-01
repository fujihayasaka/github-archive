# typed: strict
# frozen_string_literal: true

class TestRepositoryOrchestrationOnlyOneAsyncSkippedStep < RepositoryOrchestration

  step :step_zero do
    data[:step_zero_count] = (data[:step_zero_count] || 0) + 1
  end

  job_start

  step :last_one, skip: true do
    data[:last_one_count] = (data[:last_one_count] || 0) + 1
  end

end
