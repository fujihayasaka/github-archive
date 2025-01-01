# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::PastRetentionJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    disable_feature_flag(:disable_past_retention_job)
  end

  test "calls delete command" do
    freeze_time do
      without_retention_codespace = create :codespace, shutdown_at: 50.days.ago, retention_period_minutes: nil
      old_codespace = create :codespace, shutdown_at: 20.days.ago, retention_period_minutes: 10.days.in_minutes.to_i
      recent_codespace = create :codespace, shutdown_at: 6.days.ago, retention_period_minutes: 10.days.in_minutes.to_i

      Codespaces::PastRetentionJob.perform_now

      assert old_codespace.reload.deprovisioning?
      assert_enqueued_jobs 1, only: CodespacesDeleteJob
      assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: old_codespace, reason: "retention_period" }])
    end
  end

  test "skips codespaces that are not valid" do
    without_retention_codespace = create :codespace, shutdown_at: 50.days.ago, retention_period_minutes: nil
    old_codespace = create :codespace, shutdown_at: 20.days.ago, retention_period_minutes: 10.days.in_minutes.to_i
    invalid_codespace = create :codespace, shutdown_at: 20.days.ago, retention_period_minutes: 10.days.in_minutes.to_i
    invalid_codespace.update_attribute :guid, "not_a_guid"
    refute invalid_codespace.valid?

    recent_codespace = create :codespace, shutdown_at: 6.days.ago, retention_period_minutes: 10.days.in_minutes.to_i
    Codespaces::PastRetentionJob.perform_now
    assert old_codespace.reload.deprovisioning?
    assert_enqueued_jobs 1, only: CodespacesDeleteJob
    assert_equal 1, Failbot.reports.size
    assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: old_codespace, reason: "retention_period" }])
  end

  test "calls delete command even when environment data isn't valid" do
    freeze_time do
      old_codespace = create :codespace, shutdown_at: 20.days.ago, retention_period_minutes: 10.days.in_minutes.to_i
      environment_data = old_codespace.environment_data.to_h
      environment_data["id"] = "Blorg"
      old_codespace.update_attribute(:environment_data, Codespaces::Environment::Type.new.cast_value(environment_data.to_json))
      Codespaces::PastRetentionJob.perform_now

      assert old_codespace.reload.deprovisioning?
      assert_enqueued_jobs 1, only: CodespacesDeleteJob
      assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: old_codespace, reason: "retention_period" }])
    end
  end
end unless GitHub.enterprise?
