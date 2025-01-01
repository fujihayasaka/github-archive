# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::NotifyOwnerOfExpiringCodespacesJobTest < GitHub::TestCase
  test "notifies users for codespaces within 7 days of retention expiring if retention is 30 days", skip_enterprise: true do
    cs1 = create(:codespace,
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 23.days.ago - 5.minutes) # 7 days before delete
    cs2 = create(:codespace,
           owner: cs1.owner,
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 23.days.ago - 5.minutes + 12.hours) # 7.5 days before delete
    cs3 = create(:codespace,
           owner: cs1.owner,
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 25.days.ago) # 5 days before delete

    mock_mailer = mock
    mock_mailer.expects(:deliver_later).once
    CodespacesRetentionMailer.expects(:retention_warning_batch).once.with([cs1, cs2]).returns(mock_mailer)

    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cs1.owner_id)
    # Ensure it doesn't double-send the email
    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cs1.owner_id)
  end

  test "notifies users for codespaces within 7 days of retention expiring if retention is between 5 and 8 days", skip_enterprise: true do
    cs1 = create(:codespace,
           retention_period_minutes: 8.days.in_minutes.to_i,
           shutdown_at: 4.days.ago - 5.minutes) # 4 days before
    cs2 = create(:codespace,
           owner: cs1.owner,
           retention_period_minutes: 8.days.in_minutes.to_i,
           shutdown_at: 1.day.ago - 5.minutes)  # 7 days before
    mock_mailer = mock
    mock_mailer.stubs(:deliver_later)
    CodespacesRetentionMailer.expects(:retention_warning_batch).returns(mock_mailer).once.with([cs2])
    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cs1.owner_id)
  end

  test "notifies users for codespaces within 24 hours of retention expiring", skip_enterprise: true do
    cs = create(:codespace,
        retention_period_minutes: 25.hours.in_minutes.to_i,
        shutdown_at: 30.minutes.ago)
    mock_mailer = mock
    mock_mailer.stubs(:deliver_later)
    CodespacesRetentionMailer.expects(:retention_warning_batch).returns(mock_mailer).once.with([cs])
    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cs.owner_id)
  end

  test "does not notify users for copilot workspace codespaces", skip_enterprise: true do
    cw = create(:copilot_workspace,
      retention_period_minutes: 24.hours.in_minutes.to_i,
      shutdown_at: 30.minutes.ago)

    mock_mailer = mock
    mock_mailer.stubs(:deliver_later)
    CodespacesRetentionMailer.expects(:retention_warning_batch).returns(mock_mailer).never
    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cw.owner_id)
  end

  test "with mixture of retention period and expirations" do
    cs1 = create(:codespace,
           display_name: "cs1",
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 23.days.ago - 5.minutes) # 7 days before delete
    cs2 = create(:codespace,
           owner: cs1.owner,
           display_name: "cs2",
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 23.days.ago - 5.minutes + 12.hours) # 7.5 days before delete
    cs3 = create(:codespace,
           owner: cs1.owner,
           display_name: "cs3",
           retention_period_minutes: 30.days.in_minutes.to_i,
           shutdown_at: 25.days.ago) # 5 days before delete
    cs4 = create(:codespace,
           owner: cs1.owner,
           display_name: "cs4",
           retention_period_minutes: 25.hours.in_minutes.to_i,
           shutdown_at: 30.minutes.ago) # 24.5 hours before delete
    cs5 = create(:codespace,
           owner: cs1.owner,
           display_name: "cs5",
           retention_period_minutes: 25.hours.in_minutes.to_i,
           shutdown_at: 90.minutes.ago) # 23.5 hours before delete
    # This codespace should not be emailed because it was not provisioned.
    cs6 = create(:codespace, :stuck_provisioning,
           owner: cs1.owner,
           display_name: "cs6",
           retention_period_minutes: 25.hours.in_minutes.to_i,
           shutdown_at: 90.minutes.ago) # 23.5 hours before delete

    mock_mailer = mock
    mock_mailer.expects(:deliver_later).once
    CodespacesRetentionMailer.expects(:retention_warning_batch).once.with([cs1, cs2, cs5, cs4]).returns(mock_mailer)
    Codespaces::NotifyOwnerOfExpiringCodespacesJob.perform_now(cs1.owner_id)
  end
end
