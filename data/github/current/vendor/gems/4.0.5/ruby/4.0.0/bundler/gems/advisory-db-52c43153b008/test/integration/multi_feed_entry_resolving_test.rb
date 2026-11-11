# frozen_string_literal: true

require "test_helper"

# This integration test focusses on the interaction of feed entry resolution
# and advisory review updation.
#
# It tests cases where an advisory review is based off of multiple feed entries,
# with the feed entries arriving at various times in the lifecycle of the advisory review

class MultiFeedEntryResolvingTest < ActiveJob::TestCase
  # basic happy path for update (even though updates are not supported)

  # Integration test cases:
  # - Repository Advisory w/ CVE ID is broadcast.  Then NVD entry is imported. Should get joined to repo advisory's advisory-review
  # - NVD CVE is broadcast. Then repository advisory arrives w/ CVE ID set
  # - NVD CVE is rejected. Then repository advisory arrives w/ CVE ID set.  Should reopen advisory review for CVE
  # - Repository Advisory w/o CVE ID is broadcast.  Then CVE is assigned. NVD feed entry arrives.  How do these match up?
  #   - Maintainer requests CVE and also publishes advisory at same time.  Should we prevent broadcasting advisory when open cve review is present?

  test "Repository Advisory w/ CVE ID is broadcast.  Then NVD entry is imported. Should get joined to repo advisory's advisory-review" do
    # - Advisory review made based on repo advisory being published
    # - then, NVD entry with same CVE id comes along, should get attached to the same advisory review

    cve_id = "CVE-2019-1020003"
    ghsa_id = "GHSA-4444-4444-4444"
    repo_advisory_payload = FactoryBot.create :repository_advisory_curation_request_hydro_payload,
      ghsa_id: ghsa_id,
      cve_id: cve_id

    ::AdvisoryDB.hydro_publisher.publish(
      repo_advisory_payload,
      schema: "advisory_db.v0.RepositoryAdvisoryCurationRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )
    perform_enqueued_jobs(only: [ProcessRepositoryAdvisoryCurationRequestJob, ResolveFeedEntryJob]) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    feed_entry = FeedEntry.last
    assert_equal "repository_advisories", feed_entry.source
    assert_equal repo_advisory_payload["repository_advisory_content"]["ghsa_id"], feed_entry.ghsa_id
    assert_equal "repository_advisory/#{repo_advisory_payload["repository_advisory_content"]["ghsa_id"]}", feed_entry.identifier
    advisory_review = AdvisoryReview.last
    assert_equal advisory_review, feed_entry.advisory_review
    assert_equal advisory_review.ghsa_id, feed_entry.ghsa_id
    assert_equal "open", advisory_review.state

    VCR.use_cassette("nvd_CVE-2019-1020003") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
        NVDImporter.new(cve_id: cve_id).import
      end
    end

    feed_entry = FeedEntry.last
    assert_equal "nvd", feed_entry.source
    assert_equal advisory_review, feed_entry.advisory_review
    assert_equal "open", advisory_review.reload.state
  end

  test "Repository Advisory published with CVE ID matching open advisory review that has different ghsa id, should create new advisory review" do
    # - Advisory review made from NVD feed for some CVE ID, sitting in open state
    # - Repository Advisory with same CVE ID gets published
    # - Since GHSA on first advsory review will not match ghsa id on repository advisory,
    #   the feed entry for repository advisory must not be attached to advisory review for cve entry
    # - Instead, a new advisory review with ghsa
    cve_id = "CVE-2019-1020001"
    initial_advisory_review_ghsa_id = "GHSA-2222-2222-2222"
    GHSAIDGenerator.next_ghsa_id = initial_advisory_review_ghsa_id

    VCR.use_cassette("nvd_CVE-2019-1020001") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
        NVDImporter.new(cve_id: cve_id).import
      end
    end
    advisory_review_a = AdvisoryReview.last
    assert_equal initial_advisory_review_ghsa_id, advisory_review_a.ghsa_id
    assert_equal cve_id, advisory_review_a.cve_id

    repo_advisory_ghsa_id = "GHSA-3333-3333-3333"

    repo_advisory_payload = FactoryBot.create :repository_advisory_curation_request_hydro_payload,
      ghsa_id: repo_advisory_ghsa_id,
      cve_id: cve_id
    ::AdvisoryDB.hydro_publisher.publish(
      repo_advisory_payload,
      schema: "advisory_db.v0.RepositoryAdvisoryCurationRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )
    perform_enqueued_jobs(only: [ProcessRepositoryAdvisoryCurationRequestJob, ResolveFeedEntryJob]) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    feed_entry = FeedEntry.last
    assert_equal "repository_advisories", feed_entry.source
    assert_equal "repository_advisory/#{repo_advisory_ghsa_id}", feed_entry.identifier
    refute_nil feed_entry.advisory_review
    refute_equal advisory_review_a, feed_entry.advisory_review, "Repository advisory was attached to wrong advisory review"
    advisory_review_b = AdvisoryReview.last
    assert_equal advisory_review_b, feed_entry.advisory_review
    assert_equal repo_advisory_ghsa_id, advisory_review_b.ghsa_id
    refute advisory_review_b.cve_id
    # FUTURE WORK:
    # advisory_review_1 gets "merged" into advisory_review_2
    # cve_id gets moved from advisory_review_1 into advisory_review_2
    # feed entry for cve gets moved too
  end

  ["closed", "rejected"].each do |test_advisory_review_state|
    test "Feed entry attached to #{test_advisory_review_state} advisory review causes it to reopen if feed entry source is new to advisory review" do
      ghsa_id = "GHSA-vfm4-hp7p-mg26"
      cve_id = "CVE-2019-16377"
      rubysec_path = "gems/consul/CVE-2019-16377.yml"

      advisory_review = create :advisory_review,
        test_advisory_review_state.to_sym,
        feed_entry_type: :cve_feed_entry,
        ghsa_id: ghsa_id,
        cve_id: cve_id

      assert_equal 1, advisory_review.feed_entries.count
      assert_equal test_advisory_review_state, advisory_review.state

      VCR.use_cassette("rubysec_CVE-2019-16377.yml") do
        perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
          RubysecImporter.new(specific_advisory_path: rubysec_path).import
        end
      end

      advisory_review.reload
      assert_equal 2, advisory_review.feed_entries.count
      assert_equal "open", advisory_review.state
    end
  end
end
