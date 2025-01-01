# typed: true
# frozen_string_literal: true

# this is a test orchestration for testing the orchestration engine
module TestOrganizationOrchestrationModule
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { OrganizationOrchestration }
  included do
    T.bind(self, T.class_of(OrganizationOrchestration))
    # orchestration steps are executed in this order
    step :step_zero do
      data[:business_id] = business_id

      data[:step_zero_count] = (data[:step_zero_count] || 0) + 1

      if data[:step_zero_should_raise]
        raise Faraday::TimeoutError, "boom step0!"
      end
    end

    step :step_one, transaction: true, max_attempts: 2 do
      data[:step_one_count] = (data[:step_one_count] || 0) + 1

      if data[:step_one_should_raise_in_transaction]
        # raise a retryable error
        raise Faraday::TimeoutError, "boom step1!"
      end

      if data[:step_one_should_raise_once] && self.attempts == 1
        # raise a retryable error
        raise Faraday::TimeoutError, "boom step1!"
      end

      if data[:step_one_should_crash]
        # raise a non-retryable error
        raise Exception, "boom exception!"
      end
    end

    step :step_two, max_attempts: (Orchestration::MAX_SYNCHRONOUS_ATTEMPTS_LIMIT + 1) do
    end

    job_start

    step :step_two_and_a_half, skip: true do
      data[:step_two_and_a_half_count] = (data[:step_two_and_a_half_count] || 0) + 1
    end

    step :step_three do
      data[:step_three_count] = (data[:step_three_count] || 0) + 1
    end

    step :step_four do
    end

    step :step_five, max_attempts: 1 do
      data[:step_five_count] = (data[:step_five_count] || 0) + 1

      if data[:step_five_should_raise]
        # raise a retryable error
        raise Freno::Throttler::WaitedTooLong
      end
    end

    step :step_six, skip: true do
      data[:step_six_count] = (data[:step_six_count] || 0) + 1
    end

    ### end steps ###
    def step_two
      return :skipped if data[:step_two_should_skip]
      return :failed, "boom step2!" if data[:step_two_should_fail]

      data[:step_two_count] = (data[:step_two_count] || 0) + 1
      update_columns(data: data)

      if data[:step_two_should_raise]
        raise Faraday::TimeoutError, "boom step2!"
      end
    end

    def step_four
      data[:step_four_count] = (data[:step_four_count] || 0) + 1
      update_columns(data: data)

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
end

class TestOrganizationOrchestration < OrganizationOrchestration
  include TestOrganizationOrchestrationModule
end
