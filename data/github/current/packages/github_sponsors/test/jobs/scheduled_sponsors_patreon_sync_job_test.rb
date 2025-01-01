# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScheduledSponsorsPatreonSyncJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsorable_spu1, @sponsorable_spu2 = create_pair(:sponsors_patreon_user, enabled_as_sponsorable: true)
    @non_sponsorable_spu = create(:sponsors_patreon_user, :sponsor, enabled_as_sponsorable: false)
  end

  if GitHub.sponsors_enabled?
    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: ScheduledSponsorsPatreonSyncJob
    end

    test "calls the sync for sponsorable users only" do
      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      expected_jobs = [SyncSponsorsPatreonUserJob, SyncPatreonSponsorshipsJob]
      expected_users = [@sponsorable_spu1, @sponsorable_spu2]
      expected_total_jobs_enqueued = expected_jobs.size * expected_users.size

      assert_enqueued_jobs(expected_total_jobs_enqueued, only: expected_jobs) do
        ScheduledSponsorsPatreonSyncJob.perform_now
      end

      expected_jobs.each do |job_class|
        expected_users.each do |user|
          assert_enqueued_with(job: job_class, args: [user, { actor: nil }])
        end
      end
    end

    test "limits queries" do
      expected_queries = { sponsors_patreon_users: 1, sponsors_listings: 1, users: 1 }

      assert_query_count_per_table(expected_queries) do
        ScheduledSponsorsPatreonSyncJob.perform_now
      end
    end
  else
    test "does not enqueue jobs when Sponsors is disabled" do
      assert_no_enqueued_jobs do
        ScheduledSponsorsPatreonSyncJob.perform_now
      end
    end
  end
end
