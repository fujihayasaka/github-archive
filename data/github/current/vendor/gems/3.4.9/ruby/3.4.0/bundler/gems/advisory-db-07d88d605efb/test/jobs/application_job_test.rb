# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  include JobTestHelper

  test "job retries when AdvisoryDB::Lock::AlreadyLocked is raised" do
    assert_retry_on_error(AdvisoryDB::Lock::AlreadyLocked, ApplicationJob)
  end
end
