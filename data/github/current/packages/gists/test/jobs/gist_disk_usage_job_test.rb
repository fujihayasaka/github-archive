# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GistDiskUsageJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @gist = create(:gist)
  end

  test "returns early when gist to be processed does not exist" do
    result = GistDiskUsageJob.perform_now(12345)
    assert_nil result
  end

  test "returns disk usage on the gist passed to job" do
    Gist.any_instance.stubs(:exists_on_disk?).returns(:foo)
    GitRPC::Client.any_instance.stubs(:repo_disk_usage).returns(63716)
    result = GistDiskUsageJob.perform_now(@gist.id)

    assert_equal 62, result
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: GistDiskUsageJob, args: [@gist.id]
  end
end
