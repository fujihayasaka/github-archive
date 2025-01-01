# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewCreatingTest < ActionDispatch::IntegrationTest
  test "creates the advisory review" do
    user = create(:user)

    assert_difference -> { AdvisoryReview.count }, 1 do
      post "/advisory_reviews",
        headers: { "X-Okta-Username" => user.email },
        params: {
          "advisory_review" => {
            "cve_id" => "",
            "advisory_payload" => {
              "summary" => "Security lab found something",
            },
          },
        }
    end

    advisory_review = AdvisoryReview.order(:id).last
    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_equal user.login, advisory_review.paper_trail.originator

    assert_select "[data-test-selector='flash-notice']"
    assert_select "[data-test-selector='review-title']", text: "Security lab found something"

    assert_equal "in_review", advisory_review.state
    assert_equal "Security lab found something", advisory_review.summary

    assert_select "[data-test-selector='advisory-review-form']" do
      assert_form_field "[data-test-selector='advisory-review-cve-id']", value: nil
      assert_form_field "[data-test-selector='summary']", value: "Security lab found something"
    end

    # Be sure creating doesn't inadvertently withdraw the advisory review.
    assert_equal false, advisory_review.advisory_payload["withdrawn"]
  end

  test "creates with a specific CVE ID" do
    user = create(:user)

    assert_difference -> { AdvisoryReview.count }, 1 do
      post "/advisory_reviews",
        headers: { "X-Okta-Username" => user.email },
        params: {
          "advisory_review" => {
            "cve_id" => "CVE-2021-5555",
            "advisory_payload" => {
              "summary" => "Security lab found something",
            },
          },
        }
    end

    advisory_review = AdvisoryReview.order(:id).last
    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_equal user.login, advisory_review.paper_trail.originator

    assert_select "[data-test-selector='flash-notice']"
    assert_select "[data-test-selector='review-title']", text: "Security lab found something"
    assert_select "[data-test-selector='advisory-review-cve-id']", value: "CVE-2021-5555"

    assert_equal "in_review", advisory_review.state
    assert_equal "CVE-2021-5555", advisory_review.cve_id
    assert_equal "Security lab found something", advisory_review.summary
  end

  test "renders validation errors when creation fails" do
    user = create(:user)

    assert_no_difference -> { AdvisoryReview.count } do
      post "/advisory_reviews",
        headers: { "X-Okta-Username" => user.email },
        params: {
          "advisory_review" => {
            "cve_id" => "asdf", # Invalid
            "review_notes" => "Notes left by a Curator.",
            "advisory_payload" => {
              "summary" => "Security lab found something",
              "cvss_v3" => "jklm", # Invalid
            },
          },
        }
    end
    assert_response :unprocessable_entity

    assert_select "[data-test-selector='flash-error']"
    assert_select "[data-test-selector='review-title']", text: "Create an advisory review"

    assert_select "[data-test-selector='advisory-review-form']" do
      assert_form_field "[data-test-selector='advisory-review-cve-id']", value: "asdf", error: true
      assert_form_field "[data-test-selector='cvss-v3']", value: "jklm", error: true
      assert_form_field "[data-test-selector='summary']", value: "Security lab found something"
      assert_form_field "[data-test-selector='advisory-review-notes']", value: "Notes left by a Curator."
    end
  end
end
