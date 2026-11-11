# frozen_string_literal: true

require "test_helper"

class PublishCVEReviewToHydroJobTest < ActiveJob::TestCase
  test "publishes a CVERequestRespoonse message to Hydro with decision assigned for approced CVE requests" do
    cve_review = create :assigned_cve_review

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishCVEReviewToHydroJob.new.perform(cve_review_id: cve_review.id)
    end

    message = hydro_messages.last
    assert_equal :ASSIGNED, message[:decision]
    assert_equal cve_review.ghsa_id, message[:ghsa_id]
    assert_equal cve_review.comment, message[:comment]
    assert_equal cve_review.assigned_cve_id, message[:assigned_cve_id]
  end

  test "publishes a CVERequestRespoonse message to Hydro with decision not_assigned for not_assigned CVE requests" do
    cve_review = create :not_assigned_cve_review

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishCVEReviewToHydroJob.new.perform(cve_review_id: cve_review.id)
    end

    message = hydro_messages.last
    assert_equal :NOT_ASSIGNED, message[:decision]
    assert_equal cve_review.ghsa_id, message[:ghsa_id]
    assert_equal cve_review.comment, message[:comment]
    assert_equal "", message[:assigned_cve_id]
  end

  test "increments dogstat if result returns an error" do
    expect_hydro_publish_error_stat_for(PublishCVEReviewToHydroJob)

    cve_review = create :assigned_cve_review
    PublishCVEReviewToHydroJob.new.perform(cve_review_id: cve_review.id)
  end
end
