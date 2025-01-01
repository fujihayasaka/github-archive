# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::UpcomingRetentionNotificationJobTest < GitHub::TestCase
  test "enqueues a job for each codespace owner", skip_enterprise: true do
    cs = create(:codespace, retention_period_minutes: 30.days.in_minutes.to_i, shutdown_at: 29.days.ago - 5.minutes) # 1 days before delete
    non_provisioned = create(:codespace, state: :deprovisioning, retention_period_minutes: 30.days.in_minutes.to_i, shutdown_at: 29.days.ago - 5.minutes)

    assert_enqueued_with(job: Codespaces::NotifyOwnerOfExpiringCodespacesJob, args: [cs.owner_id]) do
      Codespaces::UpcomingRetentionNotificationJob.perform_now
    end
  end

  test "doesn't enqueue a job if the codespace owner only has deprovisioning codespaces in retention period", skip_enterprise: true do
    non_provisioned = create(:codespace, state: :deprovisioning, retention_period_minutes: 30.days.in_minutes.to_i, shutdown_at: 29.days.ago - 5.minutes)

    assert_no_enqueued_jobs only: Codespaces::NotifyOwnerOfExpiringCodespacesJob do
      Codespaces::UpcomingRetentionNotificationJob.perform_now
    end
  end

  test "doesn't enqueue a job if the codespace owner only has copilot workspace codespaces", skip_enterprise: true do
    copilot_workspace = create(:copilot_workspace, retention_period_minutes: 1.day.in_minutes.to_i, shutdown_at: 1.hour.ago)

    assert_no_enqueued_jobs only: Codespaces::NotifyOwnerOfExpiringCodespacesJob do
      Codespaces::UpcomingRetentionNotificationJob.perform_now
    end
  end

  test "does not enqueue a job if a notification has already been sent found codespace", skip_enterprise: true do
    travel_back
    # Ensure we're in UTC time
    Time.zone = Rails.application.config.time_zone
    travel_to Time.zone.local(2022, 10, 1)

    cs1 = create(:codespace,
          retention_period_minutes: 30.days.in_minutes.to_i,
          shutdown_at: 23.days.ago + 10.minutes)
    cs2 = create(:codespace,
          owner: cs1.owner,
          retention_period_minutes: 30.days.in_minutes.to_i,
          shutdown_at: 23.days.ago + 10.minutes + 12.hours)
    cs3 = create(:codespace,
          owner: cs1.owner,
          retention_period_minutes: 30.days.in_minutes.to_i,
          shutdown_at: 23.days.ago + 10.minutes + 24.hours) # Just outside the window for the c1/c2 batch

    mock_mailer = mock
    mock_mailer.expects(:deliver_later).once
    CodespacesRetentionMailer.expects(:retention_warning_batch).returns(mock_mailer).once.with([cs1, cs2])
    Codespaces::UpcomingRetentionNotificationJob.perform_now
    perform_enqueued_jobs(only: [Codespaces::NotifyOwnerOfExpiringCodespacesJob])

    # Travel to when cs2 will be found by UpcomingRetentionNotificationJob query
    travel 12.hours
    job_query = Codespace.
      where("retention_expires_at BETWEEN ? AND ?", 7.days.from_now - 1.hour, 7.days.from_now + 1.hour).
      where("retention_period_minutes >= ?", 8.days.in_minutes)
    assert_equal 1, job_query.count # Verify the data is set up properly
    assert_equal cs2.id, T.must(job_query.first).id

    CodespacesRetentionMailer.expects(:retention_warning_batch).never
    Codespaces::UpcomingRetentionNotificationJob.perform_now
    perform_enqueued_jobs(only: [Codespaces::NotifyOwnerOfExpiringCodespacesJob])

    # Travel to when a notification should be sent for cs3
    travel 12.hours
    mock_mailer = mock
    mock_mailer.expects(:deliver_later).once
    CodespacesRetentionMailer.expects(:retention_warning_batch).returns(mock_mailer).once.with([cs3])
    Codespaces::UpcomingRetentionNotificationJob.perform_now
    perform_enqueued_jobs(only: [Codespaces::NotifyOwnerOfExpiringCodespacesJob])
    travel_back
  end

  test "notifies users for codespaces within 7 days of retention expiring if retention is between 5 and 8 days", skip_enterprise: true do
    create(:codespace,
          retention_period_minutes: 8.days.in_minutes.to_i,
          shutdown_at: 4.days.ago - 5.minutes) # 4 days before
    cs = create(:codespace,
          retention_period_minutes: 8.days.in_minutes.to_i,
          shutdown_at: 1.day.ago - 5.minutes)  # 7 days before

    assert_enqueued_with(job: Codespaces::NotifyOwnerOfExpiringCodespacesJob, args: [cs.owner_id]) do
      Codespaces::UpcomingRetentionNotificationJob.perform_now
    end
  end

  test "notifies users for codespaces within 24 hours of retention expiring", skip_enterprise: true do
    cs = create(:codespace,
          retention_period_minutes: 25.hours.in_minutes.to_i,
          shutdown_at: 1.6.hours.ago)
    assert_enqueued_with(job: Codespaces::NotifyOwnerOfExpiringCodespacesJob, args: [cs.owner_id]) do
      Codespaces::UpcomingRetentionNotificationJob.perform_now
    end
  end
end
