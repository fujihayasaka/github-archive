# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class MarketingFormsSubmissionJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    @form_name = "test"
    @raw_data = { email: "hello@world.com", cdlProgramName: "example-name-here", marketingConsent: "optInExplicit" }
  end

  test "submitting raw data to Marketing Forms API" do
    base_url = GitHub.flipper.enabled?(:marketing_forms_api_internal_client) ? GitHub.marketing_forms_api_internal_url : GitHub.marketing_forms_api_host_url
    post_request = stub_request(:post, "#{base_url}/forms/#{@form_name}/submissions")
      .with(
        body: {
          raw_data: @raw_data.transform_values { |v|  Array(v) }
        }
      )

    MarketingFormsSubmissionJob.perform_now(form_name: @form_name, raw_data: @raw_data)

    assert_requested post_request
  end

  test "retry logic" do
    args = [{ form_name: "test", raw_data: @raw_data }]

    assert_retry_conditions(job: MarketingFormsSubmissionJob, args: args)
    assert_retry_on_error(Faraday::Error, MarketingFormsSubmissionJob, args)
  end
end
