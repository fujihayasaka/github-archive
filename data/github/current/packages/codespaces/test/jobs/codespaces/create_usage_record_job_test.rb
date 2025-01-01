# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CreateUsageRecordJobTest < GitHub::TestCase
  test "it creates a record with a valid payload" do
    cw_codespace = create(:copilot_workspace)
    cw_billing_entry = cw_codespace.billing_entry
    billing_data = create_billing_data(cw_codespace.owner, codespace: cw_codespace)
    billing_entry = billing_data[:billing_entry]
    billing_message = billing_data[:billing_message]
    tracked_usage = billing_data[:tracked_usage]
    valid_payload = {
      owner: billing_entry.codespace_owner,
      billable_owner: billing_entry.billable_owner,
      codespace_guid: billing_entry.codespace_guid,
      copilot_workspace_id: billing_entry.copilot_workspace_id,
      usage_seconds: tracked_usage.billable_duration_in_seconds,
      start_at: billing_message.period_start,
      end_at: billing_message.period_end,
    }
    assert_changes -> { Codespaces::UsageRecord.count }, from: 0, to: 1 do
      Codespaces::CreateUsageRecordJob.perform_now(valid_payload)
    end
    assert_equal tracked_usage.billable_duration_in_seconds.round, T.must(Codespaces::UsageRecord.first).usage_seconds
  end

  test "it raises an exception with an invalid payload" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Codespaces::CreateUsageRecordJob.perform_now({})
    end
  end

  def create_billing_data(user, vscs_target: "production", codespace: create(:codespace, owner: user))
    billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [codespace],
      codespace_plan_id: codespace.plan.id,
      caller_name: "codespaces/dispatch_billing_message",
      vscs_target:,
    )
    billing_entry = codespace.billing_entry
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end
