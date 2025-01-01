# typed: true
# frozen_string_literal: true

class TestIssueCommentOrchestration < IssueCommentOrchestration
  extend ActiveSupport::Concern

  # orchestration steps are executed in this order
  step :step_one do
    data[:step_one_count] = (data[:step_one_count] || 0) + 1
  end

  step :step_two, max_attempts: (Orchestration::MAX_SYNCHRONOUS_ATTEMPTS_LIMIT + 1) do
    return :skipped if data[:step_two_should_skip]
    return :failed, "boom step2!" if data[:step_two_should_fail]

    data[:step_two_count] = (data[:step_two_count] || 0) + 1

    if data[:step_two_should_raise]
      raise Faraday::TimeoutError, "boom step2!"
    end
  end

  job_start

  step :step_three do
    data[:step_three_count] = (data[:step_three_count] || 0) + 1
  end

  step :step_four do
    data[:step_four_count] = (data[:step_four_count] || 0) + 1

    if data[:step_four_should_raise]
      # raise a retryable error
      raise Faraday::TimeoutError, "boom step3!"
    end

    if data[:step_four_should_crash]
      # raise a non-retryable error
      raise Exception, "boom exception!"
    end
  end
end
