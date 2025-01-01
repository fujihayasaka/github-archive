# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class FetchOcspJobTest < GitHub::TestCase
  include JobTestHelper

  test "retry conditions" do
    assert_retry_on_dirty_exit(job: FetchOcspJob)
    assert_retry_on_throttler_error(job: FetchOcspJob)
  end
end
