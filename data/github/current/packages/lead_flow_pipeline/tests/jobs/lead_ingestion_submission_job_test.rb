# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class LeadIngestionSubmissionJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    @lead_payload = { email: "hello@world.com", cdlProgramName: "example-name-here" }
    @lead_ingestion_response = LeadIngestion::RestApiClient::Response.new(nil, payload: @lead_payload)
  end

  test "submitting payload to lead ingestion" do
    response = @lead_ingestion_response = LeadIngestion::RestApiClient::Response.new(nil, payload: @lead_payload)
    LeadIngestion::RestApiClient.expects(:put_lead).with(@lead_payload).returns(response)

    LeadIngestionSubmissionJob.perform_now(@lead_payload)
  end

  test "raising error if result has error" do
    error = Faraday::Error.new("boom")
    response = @lead_ingestion_response = LeadIngestion::RestApiClient::Response.new(nil, payload: @lead_payload, error: error)

    LeadIngestion::RestApiClient.expects(:put_lead).with(@lead_payload).returns(response)

    assert_raises LeadIngestionSubmissionJob::LeadIngestionError do
      # Calling the `perform` method directly to avoid the retry logic
      LeadIngestionSubmissionJob.new.perform(@lead_payload)
    end
  end

  test "retry logic" do
    assert_retry_on_error(
      LeadIngestionSubmissionJob::LeadIngestionError,
      LeadIngestionSubmissionJob,
      [@lead_payload]
    )
  end
end
