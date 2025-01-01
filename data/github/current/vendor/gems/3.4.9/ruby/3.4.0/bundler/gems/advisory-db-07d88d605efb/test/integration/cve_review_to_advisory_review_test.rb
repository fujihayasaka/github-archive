# frozen_string_literal: true

require "test_helper"

# This integration test focusses on how a CVE Review, when assigned and notified,
# should create/update an existing AdvisoryReview by creating a feed entry and importing it
class CVEReviewToAdvisoryReviewTest < ActionDispatch::IntegrationTest
  test "Notifying an assigned CVE Review creates an AdvisoryReview with information from the CVE Review" do
    user = create(:user)
    ghsa_id = "GHSA-g6j5-34qm-7j6c"
    cve_id = "CVE-2010-99999"
    cve_review = create :cve_review, ghsa_id: ghsa_id

    refute AdvisoryReview.exists? ghsa_id: ghsa_id
    refute AdvisoryReview.exists? cve_id: cve_id

    perform_enqueued_jobs(only: [ImportJob, ResolveFeedEntryJob]) do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: {
          assigned_cve_id: cve_id,
        },
        as: :json
    end

    assert AdvisoryReview.exists? ghsa_id: ghsa_id
    advisory_review = AdvisoryReview.find_by ghsa_id: ghsa_id
    assert_equal cve_id, advisory_review.cve_id

    # should have a single feed entry, which is the CVE Review one
    assert_equal 1, advisory_review.feed_entries.count
    assert_equal "cve_review", advisory_review.feed_entries.first.source
    assert_equal "cve_review/#{ghsa_id}", advisory_review.feed_entries.first.identifier
  end
end
