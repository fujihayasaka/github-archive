# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotTrialExitTest < GitHub::TestCase
  test "validating email" do
    signal = LeadSignal::CopilotTrialExit.new
    refute signal.valid?

    signal.email = "invalid@email"
    refute signal.valid?

    signal.email = "valid@email.com"
    assert signal.valid?
  end

  test "enqueuing a lead ingestion purchase signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: "valid@email.com",
      cDLProgramName: GitHub.copilot_trial_cancel_campaign_id,
      gitHubLastSFDCCampaignStatus: GitHub.copilot_trial_sf_status,
    }]) do
      LeadSignal::CopilotTrialExit.create(email: "valid@email.com")
    end
  end

  test "invalid signal does not enqueue" do
    assert_no_enqueued_jobs do
      LeadSignal::CopilotTrialExit.create(email: "invalid@email")
    end
  end
end
