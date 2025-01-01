# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # Allow other feature flag checks beyond the expected calls below
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_structured_payload_double_write").at_least(0).returns(true)
  end

  # tests on AdvisoryReview.find_advisory_review_for_feed_entry

  # execute a common block on a set of feed entry types
  FEED_ENTRY_TYPES = [
    :feed_entry,
    :cve_feed_entry,
    :white_source_feed_entry,
    :friends_of_php_feed_entry,
    :rubysec_feed_entry,
    :repository_advisory_feed_entry,
    :rustsec_feed_entry,
    :advisory_improvement_feed_entry,
    :malware_feed_entry,
  ].freeze

  def check_all_feed_entry_types(except: [], feed_entry_overrides: {})
    (FEED_ENTRY_TYPES - except).each do |feed_entry_type|
      feed_entry = build(feed_entry_type, feed_entry_overrides)
      yield feed_entry
    end
  end

  test "find_advisory_review_for_feed_entry returns nil if no advisory reviews" do
    AdvisoryReview.delete_all
    check_all_feed_entry_types do |feed_entry|
      assert_nil AdvisoryReview.find_advisory_review_for_feed_entry(feed_entry)
    end
  end

  test "find_advisory_review_for_feed_entry returns existing advisory review if feed entry has same cve id, and feed entry does not have ghsa id" do
    cve_id = generate(:cve_id)
    existing_advisory_review = create(:advisory_review, cve_id: cve_id)
    # exclude repository_advisory_feed_entry, since it has ghsa id defined
    # exclude malware_feed_entry, since it never has a cve id defined
    check_all_feed_entry_types(
      except: [:repository_advisory_feed_entry, :malware_feed_entry],
      feed_entry_overrides: { cve_id: cve_id },
    ) do |feed_entry|
      assert_equal(
        existing_advisory_review,
        AdvisoryReview.find_advisory_review_for_feed_entry(feed_entry),
      )
    end
  end

  test "find_advisory_review_for_feed_entry returns nil if feed entry has same cve id as existing advisory review, but feed entry does has ghsa id defined" do
    cve_id = generate(:cve_id)
    _existing_advisory_review = create(:advisory_review, cve_id: cve_id)
    feed_entry = build(:repository_advisory_feed_entry, cve_id: cve_id)
    assert_nil AdvisoryReview.find_advisory_review_for_feed_entry(feed_entry)
  end

  test "find_advisory_review_for_feed_entry returns existing advisory review if feed entry has same ghsa id as existing advisory review, even when another advisory review with same cve id exists" do
    ghsa_id = generate(:ghsa_id)
    cve_id = generate(:cve_id)
    existing_advisory_review = create(:advisory_review, ghsa_id: ghsa_id)
    _cve_advisory_review = create(:advisory_review, cve_id: cve_id)
    feed_entry = build(:repository_advisory_feed_entry, ghsa_id: ghsa_id, cve_id: cve_id)
    assert_equal(
      existing_advisory_review,
      AdvisoryReview.find_advisory_review_for_feed_entry(feed_entry),
    )
  end

  test "curation_state returns 'waiting' if the review has a CVE review and no repository advisory" do
    open_review = create(:advisory_review, :open, default_ecosystem: "npm", feed_entry_count: 0)
    create(:cve_review_feed_entry, advisory_review: open_review)
    in_review_review = create(:advisory_review, :in_review, feed_entry_count: 0)
    create(:cve_review_feed_entry, advisory_review: in_review_review)

    assert_equal "waiting", open_review.curation_state
    assert_equal "waiting", in_review_review.curation_state
  end

  test "curation_state returns 'ready_to_withdraw' if the review has the approved_to_withdraw state" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    assert_equal "ready_to_withdraw", advisory_review.curation_state
  end

  test "withdraw! correctly withdraws an advisory, even if it has a unicode character" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    advisory_review.advisory_payload["description"] = "An example description with this special character:  ’  😀."
    advisory_review.save

    # reload because we know there's a paper_trail bug that tracks changes inappropriately with unicode characters
    advisory_review.reload
    refute advisory_review.changed?
    refute advisory_review.withdrawn?

    advisory_review.withdraw!
    refute advisory_review.changed?
    assert advisory_review.withdrawn?
  end

  test "curation_state returns 'ready_to_publish' if the review has the approved_to_publish state" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)
    assert_equal "ready_to_publish", advisory_review.curation_state
  end

  test "curation_state returns 'open_create' if the review is open (with a default ecosystem) or in_review with no reviewed advisory" do
    open_review = create(:advisory_review, :open, default_ecosystem: "npm", feed_entry_type: :cve_feed_entry)
    in_review_review = create(:advisory_review, :in_review, feed_entry_type: :cve_feed_entry)
    review_with_advisory = create(:advisory_review, :open, default_ecosystem: "npm", feed_entry_type: :cve_feed_entry, create_advisory: true)
    review_with_advisory.advisory.reviewed = false

    assert_equal "open_create", open_review.curation_state
    assert_equal "open_create", in_review_review.curation_state
    assert_equal "open_create", review_with_advisory.curation_state
  end

  test "curation_state returns 'open_create' if the review has both a CVE review and a repository advisory" do
    review = create(:advisory_review, :open, default_ecosystem: "npm", feed_entry_type: :cve_review_feed_entry)
    create(:cve_review_feed_entry, advisory_review: review)

    assert_changes -> { review.reload.curation_state }, from: "waiting", to: "open_create" do
      create(:repository_advisory_feed_entry, advisory_review: review)
    end
  end

  test "curation_state returns 'open_update' if the review is open (with a default ecosystem) or in_review with a reviewed or withdrawn advisory" do
    open_review = create(:advisory_review, :open, default_ecosystem: "npm", create_advisory: true, feed_entry_type: :cve_feed_entry)
    in_review_review = create(:advisory_review, :in_review, create_advisory: true, feed_entry_type: :cve_feed_entry)

    assert_equal "open_update", open_review.curation_state
    assert_equal "open_update", in_review_review.curation_state

    advisory = Advisory.find_by(ghsa_id: open_review.ghsa_id)
    advisory.withdrawn_at = Time.current
    advisory.save!
    advisory = Advisory.find_by(ghsa_id: in_review_review.ghsa_id)
    advisory.withdrawn_at = Time.current
    advisory.save!

    assert_equal "open_update", open_review.curation_state
    assert_equal "open_update", in_review_review.curation_state
  end

  test "curation_state returns 'closed' if the review is closed or rejected, regardless of advisory" do
    closed_review = create(:advisory_review, :closed, create_advisory: true)
    rejected_review = create(:advisory_review, :rejected)

    assert_equal "closed", closed_review.curation_state
    assert_equal "closed", rejected_review.curation_state
  end

  test "curation_state returns 'published_reviewed' if the review is accepted with a published reviewed advisory" do
    advisory_review = create(:advisory_review, :accepted, create_advisory: true)

    assert_equal "published_reviewed", advisory_review.curation_state
  end

  test "curation_state returns 'published_unreviewed' if the review is accepted with a published unreviewed advisory" do
    advisory_review = create(:advisory_review, :accepted, create_advisory: true)
    advisory_review.advisory.update(reviewed: false)

    assert_equal "published_unreviewed", advisory_review.curation_state
  end

  test "curation_state returns 'withdrawn' if the review is accepted with a withdrawn advisory" do
    advisory_review = create(:advisory_review, :accepted, create_advisory: true)
    advisory = Advisory.find_by(ghsa_id: advisory_review.ghsa_id)
    advisory.withdrawn_at = Time.current
    advisory.save!

    assert_equal "withdrawn", advisory_review.curation_state
  end

  test "AdvisoryReview is scopable by curation_state" do
    waiting_review = create(:advisory_review, :curation_state_waiting)
    open_create_review = create(:advisory_review, :curation_state_open_create)
    open_update_review = create(:advisory_review, :curation_state_open_update)
    ready_to_publish_review = create(:advisory_review, :curation_state_ready_to_publish)
    ready_to_withdraw_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    published_reviewed_review = create(:advisory_review, :curation_state_published)
    published_unreviewed_review = create(:advisory_review, :curation_state_published_unreviewed)
    withdrawn_review = create(:advisory_review, :curation_state_withdrawn)
    closed_review = create(:advisory_review, :curation_state_closed)

    assert_includes AdvisoryReview.by_curation_state("waiting"), waiting_review
    assert_equal 1, AdvisoryReview.by_curation_state("waiting").count

    assert_includes AdvisoryReview.by_curation_state("open"), open_create_review
    assert_includes AdvisoryReview.by_curation_state("open"), open_update_review
    assert_equal 2, AdvisoryReview.by_curation_state("open").count

    assert_includes AdvisoryReview.by_curation_state("open_create"), open_create_review
    assert_equal 1, AdvisoryReview.by_curation_state("open_create").count

    assert_includes AdvisoryReview.by_curation_state("open_update"), open_update_review
    assert_equal 1, AdvisoryReview.by_curation_state("open_update").count

    open_update_review.advisory.update(reviewed: false)
    assert_includes AdvisoryReview.by_curation_state("open_create"), open_update_review
    assert_equal 2, AdvisoryReview.by_curation_state("open_create").count
    assert_equal 0, AdvisoryReview.by_curation_state("open_update").count

    assert_includes AdvisoryReview.by_curation_state("ready"), ready_to_publish_review
    assert_includes AdvisoryReview.by_curation_state("ready"), ready_to_withdraw_review
    assert_equal 2, AdvisoryReview.by_curation_state("ready").count

    assert_includes AdvisoryReview.by_curation_state("ready_to_publish"), ready_to_publish_review
    assert_equal 1, AdvisoryReview.by_curation_state("ready_to_publish").count

    assert_includes AdvisoryReview.by_curation_state("ready_to_withdraw"), ready_to_withdraw_review
    assert_equal 1, AdvisoryReview.by_curation_state("ready_to_withdraw").count

    assert_includes AdvisoryReview.by_curation_state("published"), published_reviewed_review
    assert_includes AdvisoryReview.by_curation_state("published"), published_unreviewed_review
    assert_equal 2, AdvisoryReview.by_curation_state("published").count

    assert_includes AdvisoryReview.by_curation_state("published_reviewed"), published_reviewed_review
    assert_equal 1, AdvisoryReview.by_curation_state("published_reviewed").count

    assert_includes AdvisoryReview.by_curation_state("published_unreviewed"), published_unreviewed_review
    assert_equal 1, AdvisoryReview.by_curation_state("published_unreviewed").count

    assert_includes AdvisoryReview.by_curation_state("withdrawn"), withdrawn_review
    assert_equal 1, AdvisoryReview.by_curation_state("withdrawn").count

    assert_includes AdvisoryReview.by_curation_state("closed"), closed_review
    assert_equal 1, AdvisoryReview.by_curation_state("closed").count
  end

  test "AdvisoryReview is scopable by campaign" do
    advisory_reviews = create_list(:advisory_review, 5)
    campaign = create(:campaign, advisory_reviews: advisory_reviews[0...2])

    assert_includes AdvisoryReview.by_campaign(campaign.id), advisory_reviews.first
    assert_includes AdvisoryReview.by_campaign(campaign.id), advisory_reviews.second
    refute_includes AdvisoryReview.by_campaign(campaign.id), advisory_reviews.last

    refute_includes AdvisoryReview.by_campaign(nil), advisory_reviews.first
    refute_includes AdvisoryReview.by_campaign(nil), advisory_reviews.second
    assert_includes AdvisoryReview.by_campaign(nil), advisory_reviews.last

    # Mixed campaign is still active
    advisory_reviews.first.record_curation_decision(type: "advisory_review", decision: "close", curator: "monalisa")
    refute_includes AdvisoryReview.by_campaign(nil), advisory_reviews.first
    refute_includes AdvisoryReview.by_campaign(nil), advisory_reviews.second
    refute_includes AdvisoryReview.by_campaign(campaign.id, "pending"), advisory_reviews.first
    assert_includes AdvisoryReview.by_campaign(campaign.id, "pending"), advisory_reviews.second
    assert_includes AdvisoryReview.by_campaign(campaign.id, "complete"), advisory_reviews.first
    refute_includes AdvisoryReview.by_campaign(campaign.id, "complete"), advisory_reviews.second

    # Complete campaign means these reviews are now back in normal curation process
    advisory_reviews.second.record_curation_decision(type: "advisory_review", decision: "close", curator: "monalisa")
    assert_includes AdvisoryReview.by_campaign(nil), advisory_reviews.first
    assert_includes AdvisoryReview.by_campaign(nil), advisory_reviews.second
  end

  test "AdvisoryReview is scopable by a list of inclusive/exclusive label ids" do
    label_1 = create(:label)
    label_2 = create(:label)
    label_3 = create(:label)
    label_4 = create(:label)
    advisory_reviews = create_list(:advisory_review, 5)

    advisory_reviews[0].labels = [label_1, label_2, label_3]
    advisory_reviews[1].labels = [label_1, label_2]
    advisory_reviews[2].labels = [label_1]
    advisory_reviews[3].labels = [label_1, label_4]

    # two included labels are ANDed
    assert_includes AdvisoryReview.by_label_ids([label_1.id.to_s, label_2.id.to_s]), advisory_reviews[0]
    assert_includes AdvisoryReview.by_label_ids([label_1.id.to_s, label_2.id.to_s]), advisory_reviews[1]
    assert_equal 2, AdvisoryReview.by_label_ids([label_1.id.to_s, label_2.id.to_s]).count

    # two excluded labels are ORed
    refute_includes AdvisoryReview.by_label_ids(["-#{label_2.id}", "-#{label_4.id}"]), advisory_reviews[0]
    refute_includes AdvisoryReview.by_label_ids(["-#{label_2.id}", "-#{label_4.id}"]), advisory_reviews[1]
    refute_includes AdvisoryReview.by_label_ids(["-#{label_2.id}", "-#{label_4.id}"]), advisory_reviews[3]
    assert_equal 2, AdvisoryReview.by_label_ids(["-#{label_2.id}", "-#{label_4.id}"]).count

    # exclusion takes precedence in an overlap
    refute_includes AdvisoryReview.by_label_ids([label_1.id.to_s, "-#{label_3.id}"]), advisory_reviews[0]
    assert_includes AdvisoryReview.by_label_ids([label_1.id.to_s, "-#{label_3.id}"]), advisory_reviews[1]
    assert_equal 3, AdvisoryReview.by_label_ids([label_1.id.to_s, "-#{label_3.id}"]).count
  end

  # tests on AdvisoryReview#auto_closable?
  test "NVD-only Advisory Review is auto-closable if description has REJECT macro" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, description: "** REJECT ** DO NOT USE THIS CANDIDATE NUMBER. ConsultIDs: none. Reason: This candidate was not assigned.")

    assert_predicate advisory_review, :auto_closable?
  end

  test "AdvisoryReview.create! works appropriately with supplied initial values" do
    ar = AdvisoryReview.create!(
      ghsa_id: GHSAIDGenerator.generate_unique_ghsa_id,
      advisory_payload: {},
    )

    refute_nil ar
    refute_nil ar.structured_advisory_payload.withdrawn
  end

  test "Advisory Review is not auto-closable when it has a second feed entry that is non-NVD" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, cve_id: "CVE-2010-1234", description: "** REJECT ** DO NOT USE THIS CANDIDATE NUMBER. ConsultIDs: none. Reason: This candidate was not assigned.")
    feed_entry = create(:rubysec_feed_entry)
    advisory_review.feed_entries << feed_entry

    refute_predicate advisory_review, :auto_closable?
  end

  test "Advisory Review is not auto-closable when it's only feed entry is not NVD" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :repository_advisory_feed_entry, cve_id: "CVE-2010-1234")

    refute_predicate advisory_review, :auto_closable?
  end

  test "Advisory Review is not auto-closable when it has a corresponding CVE review" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, cve_id: "CVE-2010-1234")
    create(:cve_review, ghsa_id: advisory_review.ghsa_id)

    refute_predicate advisory_review, :auto_closable?
  end

  test "Advisory Review is not auto-closable if it has no CVE ID" do
    advisory_review = create(:advisory_review, :open, cve_id: nil)

    refute_predicate advisory_review, :auto_closable?
  end

  test "Advisory Review is not auto-closable if it has a published advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, create_advisory: true)

    refute_predicate advisory_review, :auto_closable?
  end

  test "publishes feed entry state changes after state transitions" do
    advisory_review = create(:advisory_review, :open, feed_entry_count: 2)
    feed_entry_1, feed_entry_2 = advisory_review.feed_entries

    assert_enqueued_with(
      job: PublishChangeFeedEntryStateToHydroJob,
      args: [feed_entry_1, { old_state: "open", new_state: "in_review" }],
    ) do
      assert_enqueued_with(
        job: PublishChangeFeedEntryStateToHydroJob,
        args: [feed_entry_2, { old_state: "open", new_state: "in_review" }],
      ) do
        advisory_review.start_review!
      end
    end
  end

  test "skips feed entry state changes during creation" do
    assert_no_enqueued_jobs(only: PublishChangeFeedEntryStateToHydroJob) do
      create(:advisory_review, :open, feed_entry_count: 2)
    end
  end

  test "skips feed entry state changes if the state doesn't transition" do
    advisory_review = create(:advisory_review, :open, {
      feed_entry_count: 2,
    })

    assert_no_enqueued_jobs(only: PublishChangeFeedEntryStateToHydroJob) do
      advisory_review.update!(default_ecosystem: "something")
    end
  end

  test "reopen_closed_from_new_feed opens the pull request" do
    advisory_review = create :advisory_review,
      feed_entry_type: :repository_advisory_feed_entry
    advisory_review.reject!

    assert advisory_review.may_reopen_closed_from_new_feed?

    advisory_review.reopen_closed_from_new_feed!

    assert_equal advisory_review.reload.state, "open"
  end

  test "reopen_closed_from_new_feed requires non-NVD feed" do
    advisory_review = create :advisory_review,
      feed_entry_type: :cve_feed_entry
    advisory_review.reject!

    refute_predicate advisory_review, :may_reopen_closed_from_new_feed?
  end

  test "sends a curation stat on any state transition" do
    advisory_review = create :advisory_review

    AdvisoryDB.stats.expects(:increment).once.with("advisory_review.transition", tags: AdvisoryDB.dogtags(from: "open", to: "in_review", event: "start_review"))
    # NOTE: We have to add this next expectation to keep Mocha::Expectation happy... the above expectation only passes if *all* the calls to AdvisoryDB.stats have expectations set up
    AdvisoryDB.stats.expects(:increment).once.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    advisory_review.start_review!

    AdvisoryDB.stats.expects(:increment).once.with("advisory_review.transition", tags: AdvisoryDB.dogtags(from: "in_review", to: "rejected", event: "reject"))
    AdvisoryDB.stats.expects(:increment).once.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    advisory_review.reject!

    AdvisoryDB.stats.expects(:increment).once.with("advisory_review.transition", tags: AdvisoryDB.dogtags(from: "rejected", to: "in_review", event: "restart_review"))
    AdvisoryDB.stats.expects(:increment).once.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    advisory_review.restart_review!

    AdvisoryDB.stats.expects(:increment).once.with("advisory_review.transition", tags: AdvisoryDB.dogtags(from: "in_review", to: "accepted", event: "accept"))
    AdvisoryDB.stats.expects(:increment).once.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    advisory_review.accept!

    # make sure the stat is not sent when the state is manually updated
    AdvisoryDB.stats.expects(:increment).never.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    AdvisoryDB.stats.expects(:increment).once.with("job.enqueued", tags: AdvisoryDB.dogtags(job: :publish_change_feed_entry_state_to_hydro_job, queue: :low))
    advisory_review.update! state: "rejected"
  end

  test "updates associated campaigns when curator completes a review" do
    campaign = create(:campaign)

    advisory_review = campaign.advisory_reviews[1]
    assert_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at
    advisory_review.record_curation_decision(type: "advisory_review", decision: "close", curator: "monalisa")
    refute_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at

    advisory_review = campaign.advisory_reviews[2]
    assert_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at
    advisory_review.record_curation_decision(type: "advisory_review", decision: "ready_to_publish", curator: "monalisa")
    assert_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at

    advisory_review = campaign.advisory_reviews[3]
    assert_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at
    advisory_review.record_curation_decision(type: "advisory_publication", decision: "publish", curator: "monalisa")
    refute_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at

    advisory_review = campaign.advisory_reviews[4]
    assert_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at
    advisory_review.record_curation_decision(type: "advisory_publication", decision: "withdraw", curator: "monalisa")
    refute_nil advisory_review.advisory_reviews_campaigns.first.reviewed_at
  end

  test "#extracted_npm_id returns nil if advisory payload has no npm advisory references" do
    advisory_payload = create(:advisory_payload)
    advisory_review = create(:advisory_review, advisory_payload: advisory_payload)

    assert_nil NPMIDExtractor.extract(advisory_review)
  end

  test "#extracted_npm_id returns id if advisory payload has node security io reference" do
    references = generate_list(:url, 3)
    references << "https://nodesecurity.io/advisories/645"
    advisory_payload = create(:advisory_payload, references: references)
    advisory_review = create(:advisory_review, advisory_payload: advisory_payload)

    assert_equal 645, NPMIDExtractor.extract(advisory_review)
  end

  test "#extracted_npm_id returns id if advisory payload has npm advisory reference" do
    references = generate_list(:url, 3)
    references << "https://www.npmjs.com/advisories/1512"
    advisory_payload = create(:advisory_payload, references: references)
    advisory_review = create(:advisory_review, advisory_payload: advisory_payload)

    assert_equal 1512, NPMIDExtractor.extract(advisory_review)
  end

  test "#cvss_v3 returns the vector string from the underlying advisory payload" do
    advisory_review = create(:advisory_review, :with_cvss_v3)

    assert_equal advisory_review.advisory_payload["cvss_v3"], advisory_review.cvss_v3
  end

  test "#cvss_v4 returns the vector string from the underlying advisory payload" do
    advisory_review = create(:advisory_review, :with_cvss_v4)

    assert_equal advisory_review.advisory_payload["cvss_v4"], advisory_review.cvss_v4
  end

  test "handles unicode in advisory payload fields" do
    advisory_payload = create(:advisory_payload, {
      description: "n’t",
    })
    advisory_review = create(:advisory_review, :in_review, {
      advisory_payload: advisory_payload,
    })

    # Access description to ensure encoding handlers run
    assert_equal 3, advisory_review.reload.description.length

    assert_empty advisory_review.changes
  end

  test "an invalid blank cve_id gets automatically coerced into a valid nil cve_id" do
    # valid CVE stays valid
    advisory_review = create(:advisory_review, cve_id: "CVE-2021-5555")
    assert advisory_review.valid?
    assert_equal "CVE-2021-5555", advisory_review.cve_id

    # invalid non-blank stays invalid
    advisory_review.cve_id = "invalid but not blank"
    refute advisory_review.valid?
    assert_equal "invalid but not blank", advisory_review.cve_id

    # invalid blank becomes valid nil
    advisory_review.cve_id = ""
    assert advisory_review.valid?
    assert_nil advisory_review.cve_id
  end

  test "cwe_ids defaults to an empty array" do
    advisory_payload = create(:advisory_payload, {
      cwe_ids: nil,
    })
    advisory_review = create(:advisory_review, :in_review, {
      advisory_payload: advisory_payload,
    })

    assert_equal [], advisory_review.cwe_ids
  end

  test "revert will properly revert all fields in a changed advisory review back to its published state" do
    advisory_review = create(:advisory_review, :in_review)
    advisory = create(:advisory, ghsa_id: advisory_review.ghsa_id, cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:C/C:H/I:H/A:H")
    advisory.vulnerabilities.first.fix_commits.create(index: 0, commit_url: "https://sample.fix.commit")

    advisory_review.revert!

    advisory_payload = advisory_review.reload.advisory_payload
    assert_equal advisory.cvss_v3, advisory_payload["cvss_v3"]
    assert_equal advisory.description, advisory_payload["description"]
    assert_equal advisory.severity, advisory_payload["severity"]
    assert_equal advisory.summary, advisory_payload["summary"]
    assert_equal advisory.references.pluck(:url), advisory_payload["references"]
    assert_equal advisory.vulnerabilities_hash, advisory_payload["vulnerabilities"]
    assert_equal advisory.cwe_ids, advisory_payload["cwe_ids"]
    assert_equal advisory.withdrawn?, advisory_payload["withdrawn"]
    assert_equal advisory.vulnerabilities.map(&:fix_commits).flatten.pluck(:commit_url), advisory_payload["vulnerabilities"].values.map { |v| v["fix_commits"] }.flatten
    assert_equal "accepted", advisory_review.state
  end

  test "revert handles pending advisory improvements" do
    advisory = create(:advisory, created_at: 1.day.ago, updated_at: 1.day.ago)

    advisory_review = advisory.advisory_review
    advisory_review.update(state: "in_review")

    feed_entry = create(:advisory_improvement_feed_entry, :resolved, advisory_review: advisory_review)

    # closes PRs to inform contributors of the status
    assert_enqueued_with(
      job: ResolveAdvisoryPRsJob,
      args: [{ ghsa_id: advisory_review.ghsa_id, pr_numbers: [3], merge: false }],
    ) do
      advisory_review.revert!
    end

    # marks them not to be credited with future publications
    assert feed_entry.reload.raw_payload["rejected"]
  end

  test "overlapping_advisory_reviews returns reviews with no CVE ID but having feed entries with this CVE ID" do
    cve_id = generate(:cve_id)
    this_review = create(:advisory_review, cve_id: cve_id)
    overlapping_review_1 = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
    create(:feed_entry, advisory_review: overlapping_review_1, cve_id: cve_id)
    overlapping_review_2 = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
    create(:feed_entry, advisory_review: overlapping_review_2, cve_id: cve_id)

    overlapping_reviews = this_review.overlapping_advisory_reviews

    assert_kind_of ActiveRecord::Relation, overlapping_reviews
    assert_equal 2, overlapping_reviews.count
    assert_includes overlapping_reviews, overlapping_review_1
    assert_includes overlapping_reviews, overlapping_review_2
  end

  test "overlapping_advisory_reviews deduplicates reviews having multiple overlapping feed entries" do
    cve_id = generate(:cve_id)
    this_review = create(:advisory_review, cve_id: cve_id)
    overlapping_review = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
    create(:feed_entry, advisory_review: overlapping_review, cve_id: cve_id)
    create(:feed_entry, advisory_review: overlapping_review, cve_id: cve_id)

    overlapping_reviews = this_review.overlapping_advisory_reviews

    assert_kind_of ActiveRecord::Relation, overlapping_reviews
    assert_equal [overlapping_review], overlapping_reviews
  end

  test "overlapping_advisory_reviews returns no reviews if no overlapping feed entries exist" do
    cve_id_1 = generate(:cve_id)
    cve_id_2 = generate(:cve_id)
    this_review = create(:advisory_review, cve_id: cve_id_1)
    _other_review_1 = create(:advisory_review, cve_id: cve_id_2)
    other_review_2 = create(:advisory_review, cve_id: nil)
    create(:feed_entry, advisory_review: other_review_2, cve_id: cve_id_2)

    overlapping_reviews = this_review.overlapping_advisory_reviews

    assert_kind_of ActiveRecord::Relation, overlapping_reviews
    assert_predicate overlapping_reviews, :empty?
  end

  test "overlapping_advisory_reviews returns reviews with a CVE ID matching this review's feed entry CVE IDs" do
    cve_id_1 = generate(:cve_id)
    cve_id_2 = generate(:cve_id)
    this_review = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
    create(:feed_entry, advisory_review: this_review, cve_id: cve_id_1)
    create(:feed_entry, advisory_review: this_review, cve_id: cve_id_2)
    overlapping_review_1 = create(:advisory_review, cve_id: cve_id_1)
    overlapping_review_2 = create(:advisory_review, cve_id: cve_id_2)

    overlapping_reviews = this_review.overlapping_advisory_reviews

    assert_kind_of ActiveRecord::Relation, overlapping_reviews
    assert_equal 2, overlapping_reviews.count
    assert_includes overlapping_reviews, overlapping_review_1
    assert_includes overlapping_reviews, overlapping_review_2
  end

  test "overlapping_advisory_reviews returns no reviews if no overlapping review exist" do
    cve_id_1 = generate(:cve_id)
    cve_id_2 = generate(:cve_id)
    this_review = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
    create(:feed_entry, advisory_review: this_review, cve_id: cve_id_1)
    _other_review_1 = create(:advisory_review, cve_id: nil)
    _other_review_2 = create(:advisory_review, cve_id: cve_id_2)

    overlapping_reviews = this_review.overlapping_advisory_reviews

    assert_kind_of ActiveRecord::Relation, overlapping_reviews
    assert_predicate overlapping_reviews, :empty?
  end

  test "pending_advisory_improvements includes unpublished unrejected AdvisoryImprovement feed entries" do
    advisory = create(:advisory, created_at: 1.day.ago, updated_at: 1.day.ago)
    advisory_review = advisory.advisory_review

    published_feed_entry = create(:advisory_improvement_feed_entry, :resolved, advisory_review: advisory_review, created_at: 2.days.ago, updated_at: 2.days.ago)

    rejected_feed_entry = create(:advisory_improvement_feed_entry, :resolved, advisory_review: advisory_review)
    rejected_feed_entry.raw_payload["rejected"] = true
    rejected_feed_entry.save

    pending_feed_entry = create(:advisory_improvement_feed_entry, :resolved, advisory_review: advisory_review)

    assert advisory_review.pending_advisory_improvements.include?(pending_feed_entry)
    refute advisory_review.pending_advisory_improvements.include?(published_feed_entry)
    refute advisory_review.pending_advisory_improvements.include?(rejected_feed_entry)
  end

  test "advisory_payload is normalized before save" do
    advisory = create(:advisory)
    advisory_review = advisory.advisory_review

    advisory_review.advisory_payload["description"] = +"Some \R\N description \R\N using \R\N nonstandard \N newlines"
    advisory_review.save

    advisory_review.reload
    assert "Some \n description \n using \n nonstandard \n newlines", advisory_review.description
  end

  test "hydro_payload appropriately casts advisory ids" do
    advisory = create(:advisory)
    advisory_review = advisory.advisory_review

    advisory_id_symbols = ["npm_id", "rubysec_id", "rustsec_id", "friends_of_php_id", "white_source_id"]
    advisory_id_symbols.each { |s| advisory_review.send(:"#{s}=", 123456) }

    payload = advisory_review.hydro_payload
    advisory_id_symbols.each { |s| assert_equal "123456", payload[s.to_sym] }
  end

  test "advisory_review can be closed from approved_to_publish state" do
    advisory_review = create(:advisory_review, state: "approved_to_publish")
    advisory_review.reject!
    assert_equal "rejected", advisory_review.state
  end

  test "creating an advisory review with double write enabled creates structured data" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_structured_payload_double_write").at_least_once.returns(true)
    advisory_review = create(:advisory_review, state: "approved_to_publish")
    check_ap_and_sap_equality(advisory_review)
  end

  test "updating with double write works when increasing counts" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_structured_payload_double_write").at_least_once.returns(true)
    advisory_review = create(:advisory_review, state: "approved_to_publish")
    # sanity check
    check_ap_and_sap_equality(advisory_review)

    permute_payload(advisory_review, reference_count: 4, cwe_id_count: 4, vulnerability_count: 4)
    check_ap_and_sap_equality(advisory_review)
  end

  test "updating with double write works when decreasing counts" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_structured_payload_double_write").at_least_once.returns(true)
    advisory_review = create(:advisory_review, state: "approved_to_publish")
    # sanity check
    check_ap_and_sap_equality(advisory_review)

    permute_payload(advisory_review, reference_count: 0, cwe_id_count: 0, vulnerability_count: 0)
    check_ap_and_sap_equality(advisory_review)
  end

  test "updating with double write works when decreasing counts from something larger than 1" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_structured_payload_double_write").at_least_once.returns(true)
    advisory_review = create(:advisory_review, state: "approved_to_publish",
      advisory_payload: create(:advisory_payload, reference_count: 4, cwe_id_count: 4, vulnerability_count: 4))
    # sanity check
    check_ap_and_sap_equality(advisory_review)

    permute_payload(advisory_review, reference_count: 0, cwe_id_count: 0, vulnerability_count: 0)
    check_ap_and_sap_equality(advisory_review)
  end

  test "whitespace is removed from the advisory payload's description key before saving" do
    advisory = create(:advisory)
    advisory_review = advisory.advisory_review

    advisory_review.advisory_payload["description"] = +"testing strip of trailing whitespace (...) ❤️🤠.\n\t\n\n\r\n\v    \n"
    advisory_review.save

    advisory_review.reload
    assert_equal advisory_review.description, "testing strip of trailing whitespace (...) ❤️🤠."
  end

  def permute_payload(advisory_review, reference_count: 1, cwe_id_count: 1, vulnerability_count: 1)
    ap = build(:advisory_payload, reference_count:, cwe_id_count:, vulnerability_count:)
    advisory_review.advisory_payload["references"] = ap["references"]
    advisory_review.advisory_payload["cwe_ids"] = ap["cwe_ids"]
    advisory_review.advisory_payload["vulnerabilities"] = ap["vulnerabilities"]
    advisory_review.save!
  end

  # this test code is largely duplicated from the rake task test.
  # it's assumed this won't be needed after the validation code arrived, since it will have factored out comparison methods.
  def check_ap_and_sap_equality(advisory_review)
    sap = advisory_review.structured_advisory_payload
    ap = advisory_review.advisory_payload

    assert_equal ap["summary"], sap.summary
    assert_equal ap["description"], sap.description
    assert_equal ap["source_code_location"], sap.source_code_location
    assert_equal ap["severity"], sap.severity
    assert_equal ap["cvss_v3"], sap.cvss_v3
    assert_equal ap["withdrawn"], sap.withdrawn

    db_cwe_ids = advisory_review.structured_advisory_payload.cwe_ids.order(index: :asc)
    ap["cwe_ids"].each_with_index do |cwe_id, i|
      assert_equal cwe_id, db_cwe_ids[i].cwe_id
    end

    db_refs = advisory_review.structured_advisory_payload.references.order(index: :asc)
    ap["references"].each_with_index do |ref, i|
      assert_equal ref, db_refs[i].url
    end

    db_vulns = advisory_review.structured_advisory_payload.vulnerabilities.order(index: :asc)

    assert_equal ap["vulnerabilities"].count, db_vulns.count
    ap["vulnerabilities"].each do |i, apv|
      if apv["withdrawn"]
        assert_nil db_vulns[i]
        next
      end

      vuln = db_vulns[i]
      assert_equal apv["ecosystem"], vuln.package_ecosystem
      assert_equal apv["package_name"], vuln.package_name
      assert_equal apv["vulnerable_version_range"], vuln.vulnerable_version_range
      assert_equal apv["first_patched_version"], vuln.first_patched_version
    end
  end
end
