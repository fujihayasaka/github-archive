# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroScheduleMaintenanceOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user, from_example: :post_receive_job_test)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "schedules network maintenance for pushes with large numbers of commits" do
    maint_status = @repository.network.maintenance_status
    assert_equal "complete", maint_status

    Pushes::CommitsHelper.stub_const(:LARGE_PUSH_THRESHOLD, 1) do
      args = [@repository.network.id, { previous_status: maint_status }]
      assert_enqueued_with(job: NetworkMaintenanceJob, args: args) do
        perform_push_hydro_job(
          repository: @repository,
          job_class: HydroScheduleMaintenanceOnPushJob,
          changes: [
            { path: "foo", content: "irrelevant" },
            { path: "bar", content: "irrelevant" },
          ],
          split_changes_distinct_commits: true
        )
      end
    end
  end

  test "maintenance not scheduled for large pushes when pending" do
    maint_status = @repository.network.maintenance_status
    assert_equal "complete", maint_status

    RepositoryNetwork.any_instance.stubs(:maintenance_pending?).returns(true) do
      Pushes::CommitsHelper.stub_const(:LARGE_PUSH_THRESHOLD, 1) do
        args = [@repository.network.id, { previous_status: maint_status }]
        assert_enqueued_with(job: NetworkMaintenanceJob, args: args) do
          perform_push_hydro_job(
            repository: @repository,
            job_class: HydroScheduleMaintenanceOnPushJob,
            changes: [
              { path: "foo", content: "irrelevant" },
              { path: "bar", content: "irrelevant" },
            ],
            split_changes_distinct_commits: true
          )
        end
      end
    end
  end

  test "schedule maintenance for pushes with many ref updates, without calling large_push?" do
    Repositories::RefUpdate.any_instance.expects(:large_push?).never
    message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: 2.times.map { |t| { ref: "refs/heads#{t}", before: SecureRandom.hex(20), after: SecureRandom.hex(20) } },
      pushed_at: Time.current,
      pusher: @repository.owner_login,
      total_ref_count: 2,
      ref_batch_number: 1
    }
    assert_enqueued_with(job: NetworkMaintenanceJob) do
      Pushes::CommitsHelper.stub_const(:LARGE_REF_COUNT_THRESHOLD, 1) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_schedule_maintenance_on_push")
      end
    end
  end
end
