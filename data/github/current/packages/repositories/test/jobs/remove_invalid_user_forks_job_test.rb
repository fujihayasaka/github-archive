# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RemoveInvalidUserForksJobTest < GitHub::TestCase
  include JobTestHelper

  test "retries on dirty exit" do
    repo = create(:repository)
    assert_retry_on_dirty_exit job: RemoveInvalidUserForksJob, args: [repo.network_id]
  end
end
