# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryPublicCheckTest < ActiveSupport::TestCase
  test "returns a passed CheckResult when AdvisoryReview does not have any cve_review feed entry" do
    advisory_review = create(:advisory_review, feed_entry_type: :cve_feed_entry)

    result = RepositoryAdvisoryPublicCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a failed CheckResult when AdvisoryReview has only a single cve_review feed entry" do
    advisory_review = create(:advisory_review, feed_entry_type: :cve_review_feed_entry)

    result = RepositoryAdvisoryPublicCheck.execute_check(review: advisory_review)

    refute result.passed?
  end

  test "returns a passed CheckResult when AdvisoryReview a cve_review feed entry alongside a repository_advisory feed entry" do
    advisory_review = create(:advisory_review, feed_entry_type: :cve_review_feed_entry)
    create(:repository_advisory_feed_entry, advisory_review: advisory_review)

    result = RepositoryAdvisoryPublicCheck.execute_check(review: advisory_review)

    assert result.passed?
  end
end
