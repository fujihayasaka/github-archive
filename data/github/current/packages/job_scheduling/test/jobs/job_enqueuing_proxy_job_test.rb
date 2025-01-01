# typed: true
# frozen_string_literal: true

require "test_helper"

class JobEnqueuingProxyJobTest < GitHub::TestCase
  class TestJob < ApplicationJob
    def perform; end
  end

  test "enqueues given job" do
    assert_enqueued_with(job: JobEnqueuingProxyJobTest::TestJob, args: []) do
      JobEnqueuingProxyJob.perform_now("JobEnqueuingProxyJobTest::TestJob")
    end
  end

  test "safely handles when given a non-existent job" do
    assert_nothing_raised do
      JobEnqueuingProxyJob.perform_now("BadJob")
    end
  end
end
