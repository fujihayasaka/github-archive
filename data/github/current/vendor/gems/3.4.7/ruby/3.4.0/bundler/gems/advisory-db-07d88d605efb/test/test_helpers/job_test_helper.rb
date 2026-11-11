# frozen_string_literal: true

require "test_helper"

module JobTestHelper
  def assert_retry_on_error(error, job, args: [], kwargs: {})
    job.any_instance.stubs(:perform).raises(error, "boom")

    full_args = Array.new(args) << kwargs
    assert_enqueued_with(job: job, args: full_args) do
      job.perform_now(*full_args)
    end
  end
end
