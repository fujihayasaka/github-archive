# frozen_string_literal: true

require "test_helper"

class SendCurationQueueStatsJobTest < ActiveJob::TestCase
  # All of the advisory review queues are tested in one test
  # This is because an advisory review can have more than one feed entry / source
  # An advisory with both nvd and repository_advsories sources counts towards the repository advisory queue
  test "sends the length of the various Advisory Review queues" do
    ## Setup pure NVD advisories
    # open and in_review advisory reviews should count towards the queue depth
    create :advisory_review, :open, feed_entry_type: "cve_feed_entry"
    create :advisory_review, :curation_state_open,      feed_entry_type: "cve_feed_entry"
    create :advisory_review, :curation_state_open,      feed_entry_type: "cve_feed_entry"
    create :advisory_review, :curation_state_open,      feed_entry_type: "cve_feed_entry", create_advisory: true
    # advisory reviews in other states should not count
    create :advisory_review, :curation_state_published, feed_entry_type: "cve_feed_entry"
    create :advisory_review, :curation_state_closed,    feed_entry_type: "cve_feed_entry"

    # Allow all calls to AdvisoryDB.stats.gauge, regardless of whether the call
    # is asserted in this test.
    AdvisoryDB.stats.stubs(:gauge)

    # The expected nvd queue size
    AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 3, tags: AdvisoryDB.dogtags(queue: "nvd", new: "true"))
    AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 1, tags: AdvisoryDB.dogtags(queue: "nvd", new: "false"))

    # Setup repository advisory based advisories
    create_list :advisory_review, 5, :open, feed_entry_type: "repository_advisory_feed_entry"
    create_list :advisory_review, 4, :curation_state_open,      feed_entry_type: "repository_advisory_feed_entry"
    create_list :advisory_review, 3, :curation_state_open,      feed_entry_type: "repository_advisory_feed_entry", create_advisory: true
    # advisory reviews in other states should not count
    create :advisory_review, :curation_state_published, feed_entry_type: "repository_advisory_feed_entry"
    create :advisory_review, :curation_state_closed,    feed_entry_type: "repository_advisory_feed_entry"

    # The expected nvd queue size
    AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 9, tags: AdvisoryDB.dogtags(queue: "repository_advisories", new: "true"))
    AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 3, tags: AdvisoryDB.dogtags(queue: "repository_advisories", new: "false"))

    # Account for all the feed entry sources where the queue will be zero in this test
    (AdvisoryDB.sources - ["nvd", "repository_advisories"]).each do |source|
      AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 0, tags: AdvisoryDB.dogtags(queue: source, new: "true"))
      AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 0, tags: AdvisoryDB.dogtags(queue: source, new: "false"))
    end

    SendCurationQueueStatsJob.perform_now
  end

  test "Sends length of CVE Review queue" do
    create :cve_review, :open
    create :cve_review, :notified
    create :cve_review, :submitted

    AdvisoryDB.stats.expects(:gauge).once.with("cve_review.queue.depth", 1)

    # unrelated assertions: This is needed because when .expect is used you must specify all the calls to the expected method that are expected, whether relevant to the test or not
    AdvisoryDB.stats.expects(:gauge).once.with("job.depth", 0, tags: ["class:send_curation_queue_stats_job", "queue:low", "adapter:test"])
    AdvisoryDB.sources.each do |source|
      AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 0, tags: AdvisoryDB.dogtags(queue: source, new: "true"))
      AdvisoryDB.stats.expects(:gauge).once.with("advisory_review.queue.depth", 0, tags: AdvisoryDB.dogtags(queue: source, new: "false"))
    end

    SendCurationQueueStatsJob.perform_now
  end
end
