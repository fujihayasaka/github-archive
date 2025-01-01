# typed: strict
# frozen_string_literal: true

class TestSimpleRepositoryOrchestration < RepositoryOrchestration

  step :sync_step do
    data[:sync_step_count] = (data[:sync_step_count] || 0) + 1
  end

  job_start

  step :async_step do
    data[:async_step_count] = (data[:async_step_count] || 0) + 1
  end

end
