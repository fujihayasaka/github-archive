# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GistSynchronizeSearchIndexJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @gist = create(:gist)
  end

  test "queues to index" do
    Gist.any_instance.stubs(:gist_is_searchable?).returns(true)
    assert_enqueued_with(job: AddToSearchIndexJob) do
      GistSynchronizeSearchIndexJob.perform_now(@gist.id)
    end
  end

  test "queues to remove" do
    Gist.any_instance.stubs(:gist_is_searchable?).returns(false)
    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", 404]) do
      GistSynchronizeSearchIndexJob.perform_now(404)
    end
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: GistSynchronizeSearchIndexJob, args: [@gist.id]
  end
end
