# frozen_string_literal: true

require "test_helper"
require "rake"

class SyncAdvisoryDataRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    AdvisoryDB::Application.load_tasks if Rake::Task.tasks.empty?
    ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] = "true"
  end

  teardown do
    ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] = nil
  end

  test "rake advisory_db:sync_advisory_data enqueus dotcom publish jobs for any stale advisory data" do
    create_list(:advisory_sync_state, 5)
    stale_sync_states = create_list(:advisory_sync_state, 5, :succeeded)

    assert_enqueued_jobs(5, only: PublishAdvisoryToHydroJob) do
      assert_enqueued_with(job: PublishAdvisoryToHydroJob, args: [stale_sync_states[0].advisory]) do
        assert_enqueued_with(job: PublishAdvisoryToHydroJob, args: [stale_sync_states[1].advisory]) do
          assert_enqueued_with(job: PublishAdvisoryToHydroJob, args: [stale_sync_states[2].advisory]) do
            assert_enqueued_with(job: PublishAdvisoryToHydroJob, args: [stale_sync_states[3].advisory]) do
              assert_enqueued_with(job: PublishAdvisoryToHydroJob, args: [stale_sync_states[4].advisory]) do
                Rake::Task["advisory_db:sync_advisory_data"].execute
              end
            end
          end
        end
      end
    end
  end

  test "rake advisory_db:sync_advisory_data enqueus repo push job for stale advisory data" do
    assert_enqueued_with(job: PushAdvisoriesToRepoJob, args: [scope: :stale]) do
      Rake::Task["advisory_db:sync_advisory_data"].execute
    end
  end
end
