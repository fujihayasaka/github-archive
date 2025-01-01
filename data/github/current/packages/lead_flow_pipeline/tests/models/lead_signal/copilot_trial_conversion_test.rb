# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotTrialConversionTest < GitHub::TestCase
  test "validating email" do
    signal = LeadSignal::CopilotTrialConversion.new
    refute signal.valid?

    signal.email = "invalid@email"
    refute signal.valid?

    signal.email = "valid@email.com"
    assert signal.valid?
  end

  test "enqueuing a lead ingestion purchase signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: "valid@email.com",
      cDLProgramName: "CO-GHAI-Self-Service-Purchase-FY24-10Oct-30-CoPilot",
    }]) do
      LeadSignal::CopilotTrialConversion.create(email: "valid@email.com")
    end
  end

  test "invalid signal does not enqueue" do
    assert_no_enqueued_jobs do
      LeadSignal::CopilotTrialConversion.create(email: "invalid@email")
    end
  end
end
