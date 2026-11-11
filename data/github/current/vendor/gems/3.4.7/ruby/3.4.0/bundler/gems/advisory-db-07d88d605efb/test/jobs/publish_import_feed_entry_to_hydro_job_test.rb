# frozen_string_literal: true

require "test_helper"

class PublishImportFeedEntryToHydroJobTest < ActiveJob::TestCase
  test "publishes a create ImportFeedEntry message to Hydro" do
    feed_entry = create(:feed_entry)
    assert_predicate feed_entry.advisory_payload, :present?

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)
    end

    message = hydro_messages.last
    assert_equal feed_entry.identifier, message[:feed_entry][:identifier]
    assert_predicate message[:feed_entry][:advisory_payload], :present?
    assert_equal :CREATE, message[:action]
  end

  test "publishes an update ImportFeedEntry message to Hydro" do
    feed_entry = create(:feed_entry)
    assert_predicate feed_entry.advisory_payload, :present?

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: false)
    end

    message = hydro_messages.last
    assert_equal feed_entry.identifier, message[:feed_entry][:identifier]
    assert_predicate message[:feed_entry][:advisory_payload], :present?
    assert_equal :UPDATE, message[:action]
  end

  test "publishes the feed entry's description to Hyrdo" do
    advisory_payload = create(:advisory_payload)
    expected_description = advisory_payload["description"]
    feed_entry = create(:feed_entry, {
      advisory_payload: advisory_payload,
    })

    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)

    message = hydro_messages.last
    assert_equal expected_description, message[:feed_entry][:advisory_payload][:description]
  end

  test "publishes the feed entry's references to Hydro" do
    url_1, url_2 = generate_list(:url, 2)
    feed_entry = create(:feed_entry, {
      advisory_payload: create(:advisory_payload, {
        references: [
          url_1,
          url_2,
        ],
      }),
    })

    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)

    message = hydro_messages.last
    assert_kind_of Array, message[:feed_entry][:advisory_payload][:references]
    assert_equal 2, message[:feed_entry][:advisory_payload][:references].size
    assert_equal url_1, message[:feed_entry][:advisory_payload][:references][0][:url]
    assert_equal url_2, message[:feed_entry][:advisory_payload][:references][1][:url]
  end

  test "when feed entry has unsupported ecosystem, it reports an empty vulnerabilities list" do
    advisory_payload = create(:advisory_payload, vulnerability_count: 2)
    advisory_payload["vulnerabilities"][0]["ecosystem"] = "pip"
    advisory_payload["vulnerabilities"][1]["ecosystem"] = "unsupported"
    feed_entry = create(:feed_entry, advisory_payload: advisory_payload)

    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)

    message = hydro_messages.last
    assert_kind_of Array, message[:feed_entry][:advisory_payload][:vulnerabilities]
    # 2 in the feed entry, but only one is supported ecosystem
    assert_equal 1, message[:feed_entry][:advisory_payload][:vulnerabilities].size
  end

  test "when feed entry is attached to advisory review, it gets ghsa id from it" do
    advisory_review = create :advisory_review, feed_entry_type: "cve_feed_entry"
    feed_entry = advisory_review.feed_entries.first

    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)
    message = hydro_messages.last
    assert_equal advisory_review.ghsa_id, message[:feed_entry][:ghsa_id]
  end

  test "when feed entry is not attached to advisory review, it gets empty ghsa id " do
    feed_entry = create :feed_entry

    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)
    message = hydro_messages.last
    assert_equal "", message[:feed_entry][:ghsa_id]
  end

  test "increments dogstat if result returns an error" do
    expect_hydro_publish_error_stat_for(PublishImportFeedEntryToHydroJob)

    feed_entry = create(:feed_entry)
    PublishImportFeedEntryToHydroJob.new.perform(feed_entry, created: true)
  end
end
