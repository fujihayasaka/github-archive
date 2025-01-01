# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroNotificationsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user, from_example: :simple)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "queues DeliverRepositoryPushNotificationJob if has active settings" do
    message = {
      repository_id: @repository.id,
      ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pusher: @user.login,
      pushed_at: 1.minute.ago,
      run_hydro_job: true,
    }

    create(:hook, name: "email", active: true, events: ["push"], installation_target: @repository, config: { address: "foo@example.com" })

    expected_payload = {
      repository_id: @repository.id,
      ref: message[:ref_updates].first[:ref],
      before: message[:ref_updates].first[:before],
      after: message[:ref_updates].first[:after],
      pusher_id: @user.id,
    }

    assert_enqueued_with(job: DeliverRepositoryPushNotificationJob, args: [expected_payload]) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_notifications_on_push")
    end
  end

  test "does not queue DeliverRepositoryPushNotificationJob if settings are inactive" do
    create(:hook, name: "email", active: false, installation_target: @repository, config: { address: "foo@example.com" })
    assert_enqueued_jobs 0, only: DeliverRepositoryPushNotificationJob do
      perform_push_hydro_job(repository: @repository, job_class: HydroNotificationsOnPushJob)
    end
  end

  test "does not queue DeliverRepositoryPushNotificationJob if does not have settings" do
    assert_enqueued_jobs 0, only: DeliverRepositoryPushNotificationJob do
      perform_push_hydro_job(repository: @repository, job_class: HydroNotificationsOnPushJob)
    end
  end
end
