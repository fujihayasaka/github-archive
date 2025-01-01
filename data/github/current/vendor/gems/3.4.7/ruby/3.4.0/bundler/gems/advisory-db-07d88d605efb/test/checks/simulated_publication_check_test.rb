# frozen_string_literal: true

require "test_helper"

class SimulatedPublicationCheckTest < ActiveSupport::TestCase
  setup do
    create(:user)
  end

  test "passes if the advisory review can be published" do
    advisory_review = create(:advisory_review, :in_review)

    result = SimulatedPublicationCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert result.title.present?
    assert result.summary.present?
  end

  test "fails if the advisory review cannot be published" do
    advisory_review = create(:advisory_review, :rejected)

    result = SimulatedPublicationCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert result.title.present?
    assert result.summary.present?
  end

  test "simulate shows unexpected errors" do
    advisory_review = create(:advisory_review)
    SimulatedPublicationCheck.execute_check(review: advisory_review)

    advisory_review.advisory_payload["summary"] = nil
    advisory_review.save
    result = SimulatedPublicationCheck.execute_check(review: advisory_review)

    assert_includes result.summary, "The advisory_review being published had an unexpected error during publication"
    assert_includes result.summary, "Advisory summary can't be blank"
  end
end
