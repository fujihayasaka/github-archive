# frozen_string_literal: true

require "test_helper"

class CheckSuiteRunnerTest < ActiveSupport::TestCase
  setup do
    create(:user)
    Faraday::Connection.any_instance.stubs(:get).returns(Faraday::Response.new(status: 200))
  end

  test "checks_for_review returns different checks to run for Advisory & CVE reviews" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:assigned_cve_review)

    advisory_checks = CheckSuiteRunner.send(:checks_for_review, advisory_review)
    cve_checks = CheckSuiteRunner.send(:checks_for_review, cve_review)

    refute_equal advisory_checks, cve_checks
  end

  test "run_checks performs or queues check jobs" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)

    CheckSuiteRunner.run_checks(review: advisory_review, async: true)
    CheckSuiteRunner.run_checks(review: cve_review)

    assert_equal(true, CheckSuiteRunner.get_checks(review: advisory_review).all? { |check| check["status"] == "queued" })
    assert_equal(true, CheckSuiteRunner.get_checks(review: cve_review).all? { |check| check["status"] == "passed" })
  end

  test "get_checks pulls data for each check necessary for a given review, even if it hasn't been run" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:assigned_cve_review)

    advisory_review_check_count_before = CheckSuiteRunner.get_checks(review: advisory_review).length
    CheckSuiteRunner.run_checks(review: advisory_review)
    advisory_review_check_count_after = CheckSuiteRunner.get_checks(review: advisory_review).length

    cve_review_check_count_before = CheckSuiteRunner.get_checks(review: cve_review).length
    CheckSuiteRunner.run_checks(review: cve_review)
    cve_review_check_count_after = CheckSuiteRunner.get_checks(review: cve_review).length

    assert_equal advisory_review_check_count_before, advisory_review_check_count_after
    assert_equal cve_review_check_count_before, cve_review_check_count_after
  end

  test "checks_passed? is false for a review that hasn't run all checks" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:assigned_cve_review)

    CheckSuiteRunner.run_checks(review: advisory_review)
    CheckSuiteRunner.run_checks(review: cve_review)
    AdvisoryDB.redis.del(
      "AdvisoryReview:#{advisory_review.ghsa_id}:SupportedEcosystemCheck",
      "CVEReview:#{cve_review.ghsa_id}:CVEReviewPublishableCheck",
    )

    assert_equal false, CheckSuiteRunner.checks_passed?(review: advisory_review)
    assert_equal false, CheckSuiteRunner.checks_passed?(review: cve_review)
  end

  test "checks_passed? is false for a review that hasn't finished running checks" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:assigned_cve_review)

    CheckSuiteRunner.run_checks(review: advisory_review)
    CheckSuiteRunner.update_check_status(check_class: SupportedEcosystemCheck, review: advisory_review, status: "running")

    CheckSuiteRunner.run_checks(review: cve_review)
    CheckSuiteRunner.update_check_status(check_class: CVEReviewPublishableCheck, review: cve_review, status: "queued")

    assert_equal false, CheckSuiteRunner.checks_passed?(review: advisory_review)
    assert_equal false, CheckSuiteRunner.checks_passed?(review: cve_review)
  end

  test "checks_passed? is false for a review that has a failing check" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    cve_review = create(:undecided_cve_review)

    # Create reason for check to fail
    advisory_review.advisory_payload["vulnerabilities"] = {}

    CheckSuiteRunner.run_checks(review: advisory_review)
    CheckSuiteRunner.run_checks(review: cve_review)

    assert_equal false, CheckSuiteRunner.checks_passed?(review: advisory_review)
    assert_equal false, CheckSuiteRunner.checks_passed?(review: cve_review)
  end

  test "checks_passed? is true for a review that has passed all required checks" do
    advisory_review = create(:advisory_review, :curation_state_open)
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)

    CheckSuiteRunner.run_checks(review: advisory_review)
    CheckSuiteRunner.run_checks(review: cve_review)

    assert_equal true, CheckSuiteRunner.checks_passed?(review: advisory_review)
    assert_equal true, CheckSuiteRunner.checks_passed?(review: cve_review)
  end
end
