# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewRevertingTest < ActionDispatch::IntegrationTest
  test "an advisory review is successfully reverted" do
    ghsa_id = generate(:ghsa_id)
    advisory_review = create(:advisory_review,
      :in_review,
      ghsa_id: ghsa_id)
    advisory = create(:advisory, ghsa_id: ghsa_id)
    user = create(:user)

    original_summary = advisory.summary
    original_description = advisory.description

    # Create some changes in the advisory review to be reverted
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email },
      params: {
        "advisory_review" => {
          "advisory_payload" => {
            "summary" => "This is a test",
            "description" => "This is _only_ a test.",
          },
        },
      },
      as: :json

    put revert_advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_select "[data-test-selector=review-state]", text: "Published - Reviewed"
    assert_select "[data-test-selector=flash-notice]", text: "Advisory review #{ghsa_id} was reverted successfully!"

    assert_form_field "[data-test-selector='summary']", value: original_summary
    assert_form_field "[data-test-selector='description']", value: original_description
  end

  test "an accepted advisory review cannot be reverted" do
    advisory_review = create(:advisory_review, :accepted)
    user = create(:user)

    put revert_advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email }

    # Assert that the response status was "Unprocessable Entity".
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Published - Reviewed"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} could not be reverted!"
  end
end
