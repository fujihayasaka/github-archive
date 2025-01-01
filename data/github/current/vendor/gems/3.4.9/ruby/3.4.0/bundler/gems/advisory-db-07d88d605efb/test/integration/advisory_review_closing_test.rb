# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewClosingTest < ActionDispatch::IntegrationTest
  test "an advisory review is successfully closed" do
    advisory_review = create(:advisory_review, :open)
    user = create(:user)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/close",
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_equal user.login, advisory_review.reload.paper_trail.originator

    assert_select "[data-test-selector=review-state]", text: "Closed"
    assert_select "[data-test-selector=flash-notice]", text: "Advisory review #{advisory_review.ghsa_id} was closed successfully!"
  end

  test "an already closed advisory review cannot be closed" do
    advisory_review = create(:advisory_review, :closed)
    user = create(:user)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/close",
      headers: { "X-Okta-Username" => user.email }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Closed"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} could not be closed!"
  end
end
