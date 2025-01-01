# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewWithdrawingTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "an advisory review is approved for withdrawal" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    advisory_review = create(:advisory_review, :curation_state_open_update)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/approve",
      headers: { "X-Okta-Username" => @user.email },
      params: { approval_type: "withdraw" },
      as: :json
    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_nil advisory_review.approvals[1].approved_at
    assert_select "[data-test-selector=review-state]", text: "Ready to Withdraw"
  end

  test "an advisory is successfully withdrawn" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    refute_nil advisory_review.approvals.each(&:approved_at)
    assert_select "[data-test-selector=review-state]", text: "Withdrawn"
    assert_select "[data-test-selector=flash-notice]", text: "Advisory review #{advisory_review.ghsa_id} was withdrawn successfully!"
  end

  test "a withdrawn advisory cannot be withdrawn" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    advisory_review = create(:advisory_review, :curation_state_open_update)
    advisory_review.advisory.withdraw

    put "/advisory_reviews/#{advisory_review.ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open - Update"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} is not withdrawable!"
  end

  test "an advisory review must be open to withdraw its advisory" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    ghsa_id = generate(:ghsa_id)
    create(:advisory_review, :curation_state_closed, ghsa_id: ghsa_id)
    create(:advisory, ghsa_id: ghsa_id)

    put "/advisory_reviews/#{ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Closed"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{ghsa_id} is not withdrawable!"
  end

  test "an open advisory review must have an advisory to withdraw" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    ghsa_id = generate(:ghsa_id)
    create(:advisory_review, :curation_state_open, ghsa_id: ghsa_id)

    put "/advisory_reviews/#{ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open - New"
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{ghsa_id} is not withdrawable!"
  end

  test "withdraw fails if checks do not pass" do
    CheckSuiteRunner.stubs(checks_passed?: false) # Force failing checks
    ghsa_id = generate(:ghsa_id)
    create(:advisory_review, :curation_state_open, ghsa_id: ghsa_id)
    create(:advisory, ghsa_id: ghsa_id)

    put "/advisory_reviews/#{ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_response :unprocessable_entity
    assert_select "[data-test-selector=review-state]", text: "Open - Update"
    assert_select "[data-test-selector=flash-alert]", text: "Could not withdraw advisory review #{ghsa_id}! All checks must pass."
  end

  test "withdraw fails if advisory review does not have required approvals" do
    CheckSuiteRunner.stubs(checks_passed?: true) # Force passing checks
    advisory_review = create(:advisory_review, :curation_state_open)

    put "/advisory_reviews/#{advisory_review.ghsa_id}/withdraw",
      headers: { "X-Okta-Username" => @user.email }

    assert_equal 0, advisory_review.approvals.size
    assert_response :unprocessable_entity
    assert_select "[data-test-selector=flash-alert]", text: "Advisory review #{advisory_review.ghsa_id} is not withdrawable!"
  end
end
