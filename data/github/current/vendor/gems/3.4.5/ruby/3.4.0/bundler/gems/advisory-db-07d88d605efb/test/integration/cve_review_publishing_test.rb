# frozen_string_literal: true

require "test_helper"

class CVEReviewPublishingTest < ActionDispatch::IntegrationTest
  setup do
    CheckSuiteRunner.stubs(run_checks: true)
    CheckSuiteRunner.stubs(checks_passed?: true)
  end

  test "a CVE review is successfully published" do
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated, assigned_cve_id: "CVE-2023-0001")
    user = create(:user)

    VCR.use_cassette("cve_api_create_cve_2023_0001") do
      put "/cve_reviews/#{cve_review.ghsa_id}/publish",
        headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
        params: { pull_request_url: "https://github.com/CVEProject/cvelist/pull/123" },
        as: :json
    end
    assert_redirected_to cve_review_path(cve_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_select "[data-test-selector=review-state]", text: "Published"
    assert_select "[data-test-selector=flash-notice]", text: "CVE review #{cve_review.ghsa_id} was published successfully!"
    assert_equal 1, cve_review.mitre_cve_submissions.count
  end

  test "a non-assigned CVE review cannot be published" do
    cve_review = create(:not_assigned_cve_review, :notified, :all_fields_populated)
    user = create(:user)

    put "/cve_reviews/#{cve_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => user.email }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Closed"
    assert_select "[data-test-selector=flash-alert]", text: /CVE review #{cve_review.ghsa_id} could not be published!/
  end

  test "a non-notified CVE review cannot be published" do
    cve_review = create(:cve_review, :assigned, :all_fields_populated)
    user = create(:user)

    put "/cve_reviews/#{cve_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => user.email }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Triage"
    assert_select "[data-test-selector=flash-alert]", text: /CVE review #{cve_review.ghsa_id} could not be published!/
  end

  test "a CVE review cannot be published without a CVEProject PR URL" do
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)
    user = create(:user)

    put "/cve_reviews/#{cve_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { pull_request_url: "" },
      as: :json

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open"
    assert_select "[data-test-selector=flash-alert]", text: "CVE review #{cve_review.ghsa_id} could not be published! An error occurred: param is missing or the value is empty: pull_request_url"
  end

  test "publish cannot process if checks have not passed" do
    cve_review = create(:cve_review, :assigned, :notified)
    CheckSuiteRunner.stubs(checks_passed?: false)

    put(
      "/cve_reviews/#{cve_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" },
      # TODO: remove this param in cleanup after launch of new CVE Services API
      # publication flow
      params: { pull_request_url: "api" },
      as: :json,
    )

    refute cve_review.reload.submitted?
    assert_equal 0, MITRECVESubmission.count
    assert_response :unprocessable_entity
  end

  test "makes a request to the CVE Services API when the feature flag is enabled" do
    assert_equal 0, MITRECVESubmission.count
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)
    user = create(:user)
    cve_json_string = cve_review.cve_json_builder.to_json
    cna_json_string = JSON.generate(
      "cnaContainer" => JSON.parse(cve_json_string)["containers"]["cna"],
    )
    CVEAPI::Client.any_instance.expects(:create_cve).with(cve_review.assigned_cve_id, cna_json_string).returns({})

    put "/cve_reviews/#{cve_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { pull_request_url: "api" },
      as: :json

    assert_redirected_to cve_review_path(cve_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_select "[data-test-selector=review-state]", text: "Published"
    assert_select "[data-test-selector=flash-notice]", text: "CVE review #{cve_review.ghsa_id} was published successfully!"
    assert_equal 1, cve_review.mitre_cve_submissions.count
  end
end
