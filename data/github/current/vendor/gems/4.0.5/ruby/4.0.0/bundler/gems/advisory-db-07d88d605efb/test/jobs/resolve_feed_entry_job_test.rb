# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ResolveFeedEntryJobTest < ActiveJob::TestCase
  include JobTestHelper

  setup do
    AdvisoryDB::Features.expects(:enabled?).at_least(0).returns(false)
  end

  test "only resolve unresolved feed entries" do
    entries = Array.new(3) do |i|
      create(:feed_entry, cve_id: "CVE-1234-123#{i}", resolution_state: "resolved")
    end
    entries << create(:feed_entry, cve_id: "CVE-1234-5000", resolution_state: "resolving")
    entries << create(:feed_entry, cve_id: "CVE-1234-4242", resolution_state: "unresolved")

    assert_difference -> { AdvisoryReview.count }, 1 do
      entries.each do |entry|
        ResolveFeedEntryJob.new.perform(entry.id)
      end
    end
    entries.each(&:reload)
    assert entries.map(&:resolution_state).include?("resolving")
    assert_equal entries.last.advisory_review, AdvisoryReview.last

    assert_difference -> { AdvisoryReview.count }, 0 do
      entries.each do |entry|
        ResolveFeedEntryJob.new.perform(entry.id)
      end
    end
  end

  test "after resolving mark feed entries as resolved" do
    entry = create(:feed_entry, cve_id: "CVE-1234-4242", resolution_state: "unresolved")

    assert_changes -> { entry.reload.resolution_state }, from: "unresolved", to: "resolved" do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
  end

  test "entries without cve should create new advisory reviews" do
    entries = create_list(:feed_entry, 3, cve_id: nil, resolution_state: "unresolved")

    assert_difference -> { AdvisoryReview.count }, 3 do
      entries.each do |entry|
        ResolveFeedEntryJob.new.perform(entry.id)
      end
    end

    entries.each do |entry|
      assert_equal "resolved", entry.reload.resolution_state
    end
  end

  test "when feed entry points to a advisory review, should re-use it" do
    cve = "CVE-1234-1232"
    advisory_review = create(:advisory_review, state: "open", cve_id: cve)
    entry = create(:feed_entry, cve_id: cve, advisory_review: advisory_review, resolution_state: "unresolved")

    assert_difference -> { AdvisoryReview.count }, 0 do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
    assert_equal "resolved", entry.reload.resolution_state
  end

  test "raising an error during the resolver should not save or update the feed entry" do
    feed_entry = create(:feed_entry, resolution_state: "unresolved")
    GHSAIDGenerator.stubs(:generate_unique_ghsa_id).raises(StandardError.new("foo"))

    assert_no_difference -> { AdvisoryReview.count } do
      assert_no_changes -> { feed_entry.reload.resolution_state } do
        assert_raises StandardError do
          ResolveFeedEntryJob.new.perform(feed_entry.id)
        end
      end
    end
  end

  test "accepted advisory review should be reopened when a new feed is found" do
    cve = "CVE-1234-1232"
    advisory_review = create(:advisory_review, state: "accepted", cve_id: cve, create_advisory: true)

    entry = create(:feed_entry, resolution_state: "unresolved", cve_id: cve, advisory_review: advisory_review)
    assert_changes -> { advisory_review.reload.state }, from: "accepted", to: "in_review" do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
  end

  test "rejected advisory review should not reopen for NVD feed" do
    cve = "CVE-1234-1232"
    advisory_review = create(:advisory_review, state: "rejected", cve_id: cve)

    entry = create(:cve_feed_entry, resolution_state: "unresolved", cve_id: cve, advisory_review: advisory_review)
    assert_no_changes -> { advisory_review.reload.state } do
      ResolveFeedEntryJob.new.perform(entry.id)
    end

    assert_equal "resolved", entry.reload.resolution_state
  end

  test "rejected advisory review should reopen for non-NVD feed" do
    cve = "CVE-1234-1232"
    advisory_review = create(:advisory_review, state: "rejected", cve_id: cve)

    entry = create(:rubysec_feed_entry, resolution_state: "unresolved", cve_id: cve, advisory_review: advisory_review)
    assert_changes -> { advisory_review.reload.state }, from: "rejected", to: "open" do
      ResolveFeedEntryJob.new.perform(entry.id)
    end

    assert_equal "resolved", entry.reload.resolution_state
  end

  test "enqueues the PublishImportFeedEntryToHydroJob for the feed entry with created true when advisory review did not pre-exist" do
    entry = create(:feed_entry, cve_id: "CVE-1234-4242", resolution_state: "unresolved")
    assert_enqueued_with(job: PublishImportFeedEntryToHydroJob, args: [entry, { created: true }]) do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
  end

  test "enqueues the PublishImportFeedEntryToHydroJob for the feed entry with created true when advisory review does pre-exist, but feed entry does not" do
    create(:advisory_review, cve_id: "CVE-1234-5353")
    entry = create(:feed_entry, cve_id: "CVE-1234-5353", resolution_state: "unresolved", source: "friends_of_php")
    assert_enqueued_with(job: PublishImportFeedEntryToHydroJob, args: [entry, { created: true }]) do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
  end

  test "enqueues the PublishImportFeedEntryToHydroJob for the feed entry with created false when advisory review does pre-exist, and so does feed entry" do
    review = create(:advisory_review, cve_id: "CVE-1234-5353")
    # existing feed extry, fully resolved
    entry = create(:feed_entry, advisory_review: review, cve_id: "CVE-1234-5353", identifier: "nvd/CVE-1234-5353", resolution_state: "resolved")
    # simulate an import adding a reference
    entry.advisory_payload["references"] << "http://newreference.com/new"
    entry.save!
    entry.mark_as_unresolved

    assert_enqueued_with(job: PublishImportFeedEntryToHydroJob, args: [entry, { created: false }]) do
      ResolveFeedEntryJob.new.perform(entry.id)
    end
  end

  # We originally had a bug that was catalyzed by paper_trail,
  # this remains a useful safeguard that unicode is working as expected.
  test "updates accepted review when payload contains unicode character" do
    review = create(:advisory_review,
      advisory_payload: { "description" => "\u2022" })
    review.accept!

    entry = create(:cve_feed_entry, cve_id: review.cve_id)

    assert_changes -> { review.reload.advisory_payload } do
      assert_nothing_raised do
        ResolveFeedEntryJob.new.perform(entry.id)
      end
    end
    assert_equal entry.reload.resolution_state, "resolved"
  end

  test "when a new advisory review is opened from a source for which ai prediction is enabled, an ai prediction job is kicked off" do
    AdvisoryDB::Features.expects(:enabled?).with("gpt4_prediction").at_least_once.returns(true)
    assert_enqueued_with(
      job: Gpt4EcosystemPackagePredictionJob,
    ) do
      feed_entry = create(:friends_of_php_feed_entry, cve_id: "CVE-5555-4444", resolution_state: "unresolved")
      ResolveFeedEntryJob.new.perform(feed_entry.id)
      assert feed_entry.reload.advisory_review.open?, "should be open"
    end
  end

  test "new feed entry of the type malware and improvement will not trigger ai prediction job" do
    AdvisoryDB::Features.expects(:enabled?).with("gpt4_prediction").at_least_once.returns(true)
    assert_no_enqueued_jobs(only: Gpt4EcosystemPackagePredictionJob) do
      feed_entry_1 = create(:advisory_improvement_feed_entry, cve_id: "CVE-5555-4444")
      feed_entry_2 = create(:malware_feed_entry, cve_id: "CVE-5555-3333")
      ResolveFeedEntryJob.new.perform(feed_entry_1.id)
      ResolveFeedEntryJob.new.perform(feed_entry_2.id)
      assert feed_entry_1.reload.advisory_review.open?, "should be open"
      assert feed_entry_2.reload.advisory_review.open?, "should be open"
    end
  end

  test "when feature flag for ai prediction is disabled, no ai prediction job is triggered" do
    AdvisoryDB::Features.expects(:enabled?).with("gpt4_prediction").at_least_once.returns(false)
    assert_no_enqueued_jobs(only: Gpt4EcosystemPackagePredictionJob) do
      feed_entry = create(:friends_of_php_feed_entry, cve_id: "CVE-5555-4444", resolution_state: "unresolved")
      ResolveFeedEntryJob.new.perform(feed_entry.id)
      assert feed_entry.reload.advisory_review.open?, "should be open"
    end
  end

  class TestResolveFeedEntryJob < ResolveFeedEntryJob
    def perform(_arg)
      raise ActiveRecord::RecordNotUnique
    end
  end

  test "job retries when RecordNotUnique is raised" do
    entry = create(:feed_entry, cve_id: "CVE-1234-4242", resolution_state: "unresolved")
    assert_retry_on_error(ActiveRecord::RecordNotUnique, ResolveFeedEntryJob, args: [entry, { created: true }])
  end
end
