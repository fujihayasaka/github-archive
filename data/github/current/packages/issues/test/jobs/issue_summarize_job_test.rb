# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class IssueSummarizeJobTest < GitHub::TestCase
  include ActiveJob::TestHelper
  include JobTestHelper

  fixtures do
    @summary = create(:issue_summary)
  end

  setup do
    CopilotAPI.stubs(:enabled?).returns(true)
  end

  # TODO: Update the job and tests for the following using CAPI REST endpoints
  context "#perform" do
  end
end
