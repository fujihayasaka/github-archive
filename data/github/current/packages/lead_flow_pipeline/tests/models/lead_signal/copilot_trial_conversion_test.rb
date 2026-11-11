# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotTrialConversionTest < GitHub::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

  test "validating email" do
    signal = LeadSignal::CopilotTrialConversion.new
    refute signal.valid?

    signal.email = "invalid@email"
    refute signal.valid?

    signal.email = "valid@email.com"
    assert signal.valid?
  end

  test "generating id" do
    signal = LeadSignal::CopilotTrialConversion.new(email: "valid@email.com")
    assert signal.id
    assert_match(UUID_PATTERN, signal.id)
  end

  test "generating consistent digest" do
    signal1 = LeadSignal::CopilotTrialConversion.new(email: "valid@email.com")
    signal2 = LeadSignal::CopilotTrialConversion.new(email: "valid@email.com")
    assert_equal signal1.digest, signal2.digest
  end

  test "signal data" do
    signal = LeadSignal::CopilotTrialConversion.new(email: "valid@email.com")
    expected_data = {
      id: signal.id,
      email: "valid@email.com",
      cDLProgramName: "CO-GHAI-Self-Service-Purchase-FY24-10Oct-30-CoPilot",
    }

    assert_equal expected_data, signal.data
  end

  test "enqueuing a lead ingestion purchase signal" do
    signal = LeadSignal::CopilotTrialConversion.new(email: "valid@email.com")

    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [signal.data]) do
      signal.save
    end
  end

  test "invalid signal does not enqueue" do
    assert_no_enqueued_jobs do
      LeadSignal::CopilotTrialConversion.create(email: "invalid@email")
    end
  end
end
