# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GitHubJobsGistFlaggedByUserTest < GitHub::TestCase
  include JobTestHelper

  context ".perform" do
    test "adds gist author to Possible Spammer Queue" do
      user = create(:user)
      gist = create(:gist)
      GlobalInstrumenter.expects(:instrument).with(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: gist.user.global_relay_id,
          additional_context: "RESQUE",
          origin: :RESQUE,
          queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
        },
      )

      GistFlaggedByUserJob.perform_now(gist.id, user.id)
    end
  end

  test "retries on dirty exit" do
    user = create(:user)
    gist = create(:gist)
    assert_retry_on_dirty_exit job: GistFlaggedByUserJob, args: [gist.id, user.id]
  end
end
