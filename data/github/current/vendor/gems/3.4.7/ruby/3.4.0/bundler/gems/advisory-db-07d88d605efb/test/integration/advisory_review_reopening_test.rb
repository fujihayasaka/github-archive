# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewReopeningTest < ActionDispatch::IntegrationTest
  test "an advisory review is successfully reopened" do
    advisory_review = create(:advisory_review, :curation_state_closed, feed_entry_type: :cve_feed_entry)
    user = create(:user)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/reopen",
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_equal user.login, advisory_review.reload.paper_trail.originator

    assert_select "[data-test-selector=review-state]", text: "Open - New"
    assert_select "[data-test-selector=flash-notice]", text: "Advisory review #{advisory_review.ghsa_id} was reopened successfully!"
  end

  test "an already open advisory review cannot be reopened" do
    advisory_review = create(:advisory_review, :curation_state_open_create)
    user = create(:user)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/reopen",
      headers: { "X-Okta-Username" => user.email }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open - New"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} could not be reopened!"
  end
end
