# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewPublishingTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    CheckSuiteRunner.stubs(run_checks: true)
    CheckSuiteRunner.stubs(checks_passed?: true)
  end

  test "an advisory review is approved for publication" do
    advisory_review = create(:advisory_review, :curation_state_open)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/approve",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { approval_type: "publish" },
      as: :json

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 1, advisory_review.approvals.size
    assert_select "[data-test-selector=review-state]", text: "Ready to Publish"
  end

  test "an advisory review is successfully published" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 2, advisory_review.approvals.size
    assert_select "[data-test-selector=review-state]", text: "Published - Reviewed"
    assert_select "[data-test-selector=flash-notice]", text: "Advisory review #{advisory_review.ghsa_id} was published successfully!"
  end

  test "a published advisory review cannot be published" do
    advisory_review = create(:advisory_review, :accepted, feed_entry_type: :cve_feed_entry)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Published - Reviewed"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} could not be published!"
  end

  test "publish fails if checks do not pass" do
    CheckSuiteRunner.stubs(checks_passed?: false)
    advisory_review = create(:advisory_review, :curation_state_open)
    advisory_review.advisory_payload["vulnerabilities"] = {}
    advisory_review.save

    put "/advisory_reviews/#{advisory_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open - New"
    assert_select "[data-test-selector=flash-alert]", text: "Could not publish advisory review #{advisory_review.ghsa_id}! All checks must pass."
  end

  test "publish fails if advisory review does not have required approvals" do
    advisory_review = create(:advisory_review, :curation_state_open)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/publish",
      headers: { "X-Okta-Username" => @user.email }

    assert_equal 0, advisory_review.approvals.size
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} could not be published! An error occurred."
  end
end
