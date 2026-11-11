# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotTrialExitTest < GitHub::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

  test "validating email" do
    signal = LeadSignal::CopilotTrialExit.new
    refute signal.valid?

    signal.email = "invalid@email"
    refute signal.valid?

    signal.email = "valid@email.com"
    assert signal.valid?
  end

  test "generating id" do
    signal = LeadSignal::CopilotTrialExit.new(email: "valid@email.com")
    assert signal.id
    assert_match(UUID_PATTERN, signal.id)
  end

  test "generating consistent digest" do
    signal1 = LeadSignal::CopilotTrialExit.new(email: "valid@email.com")
    signal2 = LeadSignal::CopilotTrialExit.new(email: "valid@email.com")
    assert_equal signal1.digest, signal2.digest
  end

  test "signal data" do
    signal = LeadSignal::CopilotTrialExit.new(email: "valid@email.com")
    expected_data = {
      id: signal.id,
      email: "valid@email.com",
      cDLProgramName: GitHub.copilot_trial_cancel_campaign_id,
      gitHubLastSFDCCampaignStatus: GitHub.copilot_trial_sf_status,
    }

    assert_equal expected_data, signal.data
  end

  test "enqueuing a lead ingestion purchase signal" do
    signal = LeadSignal::CopilotTrialExit.new(email: "valid@email.com")

    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [signal.data]) do
      signal.save
    end
  end

  test "invalid signal does not enqueue" do
    assert_no_enqueued_jobs do
      LeadSignal::CopilotTrialExit.create(email: "invalid@email")
    end
  end
end
