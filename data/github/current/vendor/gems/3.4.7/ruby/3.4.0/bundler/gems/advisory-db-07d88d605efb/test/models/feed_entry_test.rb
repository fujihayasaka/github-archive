# frozen_string_literal: true

require "test_helper"

class FeedEntryTest < ActiveSupport::TestCase
  test "flags changes to the advisory payload as significant" do
    feed_entry = create(:feed_entry, cve_id: nil, white_source_id: nil)
    raw_payload = feed_entry.raw_payload.dup
    advisory_payload = feed_entry.advisory_payload.dup

    # Creation is always significant.
    assert_predicate feed_entry, :previous_changes_significant?

    raw_payload["new"] = "information"
    feed_entry.update!(raw_payload: raw_payload)

    # Only advisory payload updates are significant.
    refute_predicate feed_entry, :previous_changes_significant?

    advisory_payload["new"] = "information"
    feed_entry.update!(advisory_payload: advisory_payload)

    # Advisory payload updates are significant.
    assert_predicate feed_entry, :previous_changes_significant?

    feed_entry.update!(advisory_payload: advisory_payload)

    # Advisory payload updates are only significant if there are changes.
    refute_predicate feed_entry, :previous_changes_significant?

    raw_payload["newer"] = "information"
    advisory_payload["newer"] = "information"
    feed_entry.update!(raw_payload: raw_payload, advisory_payload: advisory_payload)

    # Advisory payload updates are significant alongside other updates.
    assert_predicate feed_entry, :previous_changes_significant?

    feed_entry.update!(cve_id: generate(:cve_id))

    # CVE ID changes are significant.
    assert_predicate feed_entry, :previous_changes_significant?
  end

  test "unresolved_changes flags changes to the advisory payload unless they match advisory review" do
    advisory_review = create(:advisory_review)
    feed_entry = advisory_review.feed_entries.first
    feed_entry.mark_as_resolved

    # a key updated different should be significant
    feed_entry.cve_id = "CVE-0000-0000"
    feed_entry.advisory_payload["summary"] = "this summary is new"
    feed_entry.save!
    feed_entry.mark_as_unresolved
    assert feed_entry.unresolved_changes["cve_id"].present?
    assert feed_entry.unresolved_changes["advisory_payload"].present?
    assert feed_entry.unresolved_changes["advisory_payload"]["summary"].present?
    refute feed_entry.unresolved_changes["advisory_payload"]["description"].present?
    feed_entry.mark_as_resolved

    # a collection key w/ a removal should be significant
    feed_entry.advisory_payload["references"].shift
    feed_entry.save!
    feed_entry.mark_as_unresolved
    assert feed_entry.unresolved_changes["advisory_payload"].present?
    refute feed_entry.unresolved_changes["advisory_payload"]["summary"].present?
    assert feed_entry.unresolved_changes["advisory_payload"]["references"].present?
    feed_entry.mark_as_resolved

    # mixed same/different updates should have some significant
    feed_entry.advisory_payload["summary"] = advisory_review.advisory_payload["summary"]
    feed_entry.advisory_payload["description"] = "this description is new"
    feed_entry.save!
    feed_entry.mark_as_unresolved
    FeedEntry.mark_as_resolving(feed_entry.id)
    refute feed_entry.unresolved_changes["cve_id"].present?
    assert feed_entry.unresolved_changes["advisory_payload"].present?
    refute feed_entry.unresolved_changes["advisory_payload"]["summary"].present?
    assert feed_entry.unresolved_changes["advisory_payload"]["description"].present?
    feed_entry.mark_as_resolved

    # a key updated the same should not be significant
    feed_entry.cve_id = advisory_review.cve_id
    feed_entry.advisory_payload["description"] = advisory_review.advisory_payload["description"]
    feed_entry.save!
    FeedEntry.mark_as_resolving(feed_entry.id)
    refute feed_entry.unresolved_changes["cve_id"].present?
    refute feed_entry.unresolved_changes["advisory_payload"].present?
    feed_entry.mark_as_resolved

    # multiple change set resulting back to the original should not be significant
    feed_entry.advisory_payload["summary"] = "this summary is new"
    feed_entry.save!
    feed_entry.mark_as_unresolved
    feed_entry.advisory_payload["summary"] = advisory_review.advisory_payload["summary"]
    feed_entry.save!
    FeedEntry.mark_as_resolving(feed_entry.id)
    refute feed_entry.unresolved_changes["advisory_payload"].present?
    feed_entry.mark_as_resolved

    # no attached advisory review
    advisory_review = create(:advisory_review)
    feed_entry = create(:feed_entry, cve_id: advisory_review.cve_id, advisory_payload_overrides: advisory_review.advisory_payload)
    assert feed_entry.unresolved_changes["cve_id"].present?
    assert feed_entry.unresolved_changes["advisory_payload"].present?
    assert feed_entry.unresolved_changes["advisory_payload"]["summary"].present?
    assert feed_entry.unresolved_changes["advisory_payload"]["description"].present?
  end

  test "defaults ml_reject_prediction to ml_unknown" do
    feed_entry_1 = FeedEntry.new
    assert_equal "unknown", feed_entry_1.ml_reject_prediction
    feed_entry_2 = build :feed_entry
    assert_equal "unknown", feed_entry_2.ml_reject_prediction
    feed_entry_2.save!
    assert_equal "unknown", feed_entry_2.reload.ml_reject_prediction
  end

  test "includes CWE IDs in the hydro_payload" do
    cwe_ids = ["CWE-79", "CWE-200"]
    feed_entry = create(:feed_entry, advisory_payload_overrides: { cwe_ids: cwe_ids })

    assert_equal cwe_ids, feed_entry.hydro_payload[:advisory_payload][:cwe_ids]
  end

  test "includes an empty array for CWE IDs if CWE IDs are not provided" do
    feed_entry = create(:feed_entry, advisory_payload_overrides: { cwe_ids: nil })

    assert_equal [], feed_entry.hydro_payload[:advisory_payload][:cwe_ids]
  end

  test "includes the cvss_v3 in the hydro_payload" do
    cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"
    feed_entry = create(:feed_entry, advisory_payload_overrides: { cvss_v3: cvss_v3 })

    assert_equal cvss_v3, feed_entry.hydro_payload[:advisory_payload][:cvss_v3]
  end

  # Curation stats

  test "increments a stat when created" do
    source = "rubysec"

    AdvisoryDB.stats.expects(:increment).once.with(
      "feed_entry.create",
      tags: AdvisoryDB.dogtags(source: source),
    )

    create(:feed_entry, source: source)
  end

  test "increments a stat when updated" do
    feed_entry = create(:feed_entry)

    AdvisoryDB.stats.expects(:increment).once.with(
      "feed_entry.update",
      tags: AdvisoryDB.dogtags(source: feed_entry.source),
    )

    feed_entry.update(advisory_payload: { description: "Updated!" })
  end
end
