# frozen_string_literal: true

require "test_helper"

class PublishChangeFeedEntryStateToHydroJobTest < ActiveJob::TestCase
  test "publishes a ChangeFeedEntryState message to Hydro with old and new state" do
    feed_entry = create :feed_entry

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishChangeFeedEntryStateToHydroJob.new.perform(feed_entry, old_state: "CLOSED", new_state: "OPEN")
    end

    message = hydro_messages.last
    assert_equal :CLOSED, message[:old_state]
    assert_equal :OPEN, message[:new_state]
    hash = {
      source: feed_entry.source.upcase.to_sym,
      identifier: feed_entry.identifier,
      cve_id: "",
      white_source_id: "",
      advisory_payload: { description: feed_entry.advisory_payload["description"],
                          severity: feed_entry.advisory_payload["severity"].upcase.to_sym,
                          references: feed_entry.advisory_payload["references"].map { |r| { url: r } },
                          vulnerabilities:
                            feed_entry.advisory_payload["vulnerabilities"].values.map do |v|
                              {
                                package_ecosystem: v["ecosystem"].upcase.to_sym,
                                package_name: v["package_name"],
                                vulnerable_version_range: v["vulnerable_version_range"],
                                first_patched_version: v["first_patched_version"],
                                affected_functions: [], # Leave empty until we remove it from the Protobuf
                                affected_functions_json: "", # Leave empty until we remove it from the Protobuf
                              }
                            end,
                          withdrawn: false,
                          cvss_v3: feed_entry.advisory_payload["cvss_v3"],
                          cvss_v4: feed_entry.advisory_payload["cvss_v4"],
                          cwe_ids: feed_entry.advisory_payload["cwe_ids"] },
      created_at: Google::Protobuf::Timestamp.new(seconds: feed_entry.created_at.to_i).to_h,
      updated_at: Google::Protobuf::Timestamp.new(seconds: feed_entry.updated_at.to_i).to_h,
      ghsa_id: "",
      npm_id: "",
    }
    assert_equal hash, message[:feed_entry]
  end

  test "increments dogstat if result returns an error" do
    expect_hydro_publish_error_stat_for(PublishChangeFeedEntryStateToHydroJob)

    feed_entry = create :feed_entry
    PublishChangeFeedEntryStateToHydroJob.new.perform(feed_entry, old_state: "CLOSED", new_state: "OPEN")
  end
end
