# frozen_string_literal: true

require "test_helper"
require "webmock"

class EpssControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include WebMock::API
  WebMock.enable!

  setup do
    @user = create(:user)
  end

  test "calling the controller calls github and renders epss data" do
    ghsa_id = "GHSA-w4pr-4vgj-hffh"

    stub_request(:post, "https://api.github.com/app/installations/123456/access_tokens")
      .to_return(
        body: { token: 123, expires_at: 1.hour.from_now }.to_json,
        headers: { content_type: "application/json" },
      )
    AdvisoryDB.github.expects(:get)
      .with("/advisories/#{ghsa_id}")
      .returns({ "epss" => { "percentage" => 0.45678, "percentile" => 0.12345 } }.with_indifferent_access) # use indifferent access because octokit returns similarly

    get "/epss/GHSA-w4pr-4vgj-hffh",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=epss-percentage]", text: "45.678%"
    assert_select "[data-test-selector=epss-percentile]", text: "12th percentile"
  end

  test "calling the controller renders error information when gh/gh call fails" do
    ghsa_id = "GHSA-w4pr-4vgj-hffh"

    stub_request(:post, "https://api.github.com/app/installations/123456/access_tokens")
      .to_return(
        body: { token: 123, expires_at: 1.hour.from_now }.to_json,
        headers: { content_type: "application/json" },
      )
    AdvisoryDB.github.expects(:get)
      .with("/advisories/#{ghsa_id}")
      .raises(Octokit::ClientError.new)

    get "/epss/GHSA-w4pr-4vgj-hffh",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=failed-epss-fetch-icon]"
    assert_select "[data-test-selector=epss-error-text]", text: "Error fetching EPSS data"
  end

  test "calling the controller renders no data found when gh/gh call has no epss data" do
    ghsa_id = "GHSA-w4pr-4vgj-hffh"

    stub_request(:post, "https://api.github.com/app/installations/123456/access_tokens")
      .to_return(
        body: { token: 123, expires_at: 1.hour.from_now }.to_json,
        headers: { content_type: "application/json" },
      )
    AdvisoryDB.github.expects(:get)
      .with("/advisories/#{ghsa_id}")
      .returns({}.with_indifferent_access) # use indifferent access because octokit returns similarly

    get "/epss/GHSA-w4pr-4vgj-hffh",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=epss-no-data-text]", text: "No EPSS data found for advisory."
  end
end
