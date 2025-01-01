# frozen_string_literal: true

require "test_helper"

class CVEReviewPublishableCheckTest < ActiveSupport::TestCase
  test "returns a passed CheckResult cve review is assigned" do
    cve_review = create(:assigned_cve_review)
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    assert result.passed?
  end

  test "returns a failed CheckResult cve review is assigned but missing assgigned_cve_id" do
    cve_review = create(:assigned_cve_review, assigned_cve_id: nil)
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns a failed CheckResult cve review is not_assigned" do
    cve_review = create(:not_assigned_cve_review)
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns failed CheckResult if decision is undecided" do
    cve_review = create(:cve_review)
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns failed CheckResult if CVSS is not a valid 3.x cvss" do
    cve_review = create(:assigned_cve_review)
    cve_review.update_attribute(:cvss_vectorString, "AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:H")
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "can handle an emojii in the comment" do
    cve_review = create(:assigned_cve_review, comment: "thanks :) 🤠 ❤️  有用")
    result = CVEReviewPublishableCheck.execute_check(review: cve_review)
    assert result.passed?
  end
end
