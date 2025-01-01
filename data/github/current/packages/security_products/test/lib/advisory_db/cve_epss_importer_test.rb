# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "cve_epss_import_assertions"

class CVEEPSSImporterTest < GitHub::TestCase
  include CVEEPSSImportAssertions

  setup do
    @epss_test_data = File.read("packages/security_products/test/lib/advisory_db/epss_test_data.csv").split("\n")
    @ingest_for_date = "2024-01-13T00:00:00.000Z".to_time(:utc)
  end

  test "ingests all data in hydro payload" do
    assert CVEEPSS.count.zero?
    ingest_test_data

    assert_cve_epss_fully_matches
  end

  test "when we ingest, we call synchronize search index on behalf of the model", skip_enterprise: true do
    vulnerability_1 = create(:vulnerability, cve_id: "CVE-1999-0001")
    vulnerability_2 = create(:vulnerability, cve_id: "CVE-1999-0002")
    vulnerability_3 = create(:vulnerability, cve_id: "CVE-1999-0003")

    # We crack open how vulnerability implements synchronize here because we don't have a good way to expect on the
    # db loaded records as the importer runs.
    Search.expects(:add_to_search_index).with("vulnerability", vulnerability_1.id)
    Search.expects(:add_to_search_index).with("vulnerability", vulnerability_2.id)
    Search.expects(:add_to_search_index).with("vulnerability", vulnerability_3.id)

    @epss_test_data = ["CVE-1999-0001,0.01384,0.74293",
      "CVE-1999-0002,0.01333,0.74291",
      "CVE-1999-0003,0.02383,0.84295"]
    ingest_test_data
  end

  test "nothing bad happens if we ingest data subsets (currently we have no deletion scenarios)" do
    assert CVEEPSS.count.zero?
    ingest_test_data

    assert_cve_epss_fully_matches

    old_epss_data = @epss_test_data
    @epss_test_data = []
    ingest_test_data

    assert_cve_epss_fully_matches(epss_test_data: old_epss_data)
  end

  test "no changes are observed when processing the same data" do
    ingest_test_data

    assert_cve_epss_fully_matches

    assert_no_difference("CVEEPSS.count") do
      ingest_test_data
    end

    assert_cve_epss_fully_matches
  end

  test "ingesting one changed record updates just that record" do
    ingest_test_data
    assert_cve_epss_fully_matches
    max_updated_at = CVEEPSS.maximum(:updated_at)

    # Sleep for 2 ms to at least force a different timestamp.
    # This is not used in any mathematical calculations (just that one message needs to be verifiably "after" the other).
    # Timecop doesn't work with the bulk procedures used in upsert_all, so we need to rely on more archaic methods of verifying timing.
    sleep 0.002

    # Slightly alter the test data data
    @epss_test_data[0] = "CVE-1999-0001,0.01383,0.74295"
    new_ingestion_date = @ingest_for_date + 1.day
    # Create a matching Vulnerability and Advisory
    create(:vulnerability, cve_id: "CVE-1999-0001")
    create(:repository_advisory, cve_id: "CVE-1999-0001")

    ingest_test_data(ingestion_date: new_ingestion_date)

    found_records = CVEEPSS.where("updated_at > ?", max_updated_at)
    refute_empty found_records
    assert_equal 1, found_records.count
    record = found_records[0]
    # validate our manual one off change for coherence
    assert_equal ["CVE-1999-0001", 0.01383, 0.74295], [record.cve_id, record.percentage, record.percentile]
    assert_equal new_ingestion_date.to_date, record.calculation_date
    assert_cve_epss_fully_matches(ignore_ingestion_dates: true)
  end

  test "[re]ingesting an EPSS record whose CVE-ID does not have a matching ADB Vulnerability entry does not cause problems" do # This is expect to happen in prod, details: https://github.com/github/dependabot-updates/issues/8462
    # initial ingest
    @epss_test_data = ["CVE-1999-MISSING,0.03456,0.74293,"]
    ingest_test_data
    assert_cve_epss_fully_matches

    # Now re-ingest but with a difference percentage to trigger reprocessing
    @epss_test_data = ["CVE-1999-MISSING,0.03456,0.84293,"]
    ingest_test_data
    assert_cve_epss_fully_matches
  end

  test "ingest_only_significant_percentile_updates works to limit what is processed during ingestion" do
    # reset test data to a known set to test partial processing in way that is obvious to test maintainers

    percentile_1 = 0.74295
    percentile_2 = 0.63184

    @epss_test_data = ["CVE-1999-0001,0.02345,#{percentile_1}",
                       "CVE-1999-0002,0.03456,#{percentile_2}"]
    # Create matching Vulnerabilities and Advisories
    create(:vulnerability, cve_id: "CVE-1999-0001")
    create(:repository_advisory, cve_id: "CVE-1999-0001")
    create(:vulnerability, cve_id: "CVE-1999-0002")
    create(:repository_advisory, cve_id: "CVE-1999-0002")

    ingest_test_data(ingest_only_significant_percentile_updates: true)
    assert_cve_epss_fully_matches

    percentile_1 = 0.75345 # rounds up to a different two decimal place value, .75
    percentile_2 = 0.63501 # rounds up to a different two decimal place value, .64
    @epss_test_data = ["CVE-1999-0001,0.02345,#{percentile_1}",
                       "CVE-1999-0002,0.03456,#{percentile_2}"]

    ingest_test_data(ingest_only_significant_percentile_updates: true)

    assert_equal CVEEPSS.find_by(cve_id: "CVE-1999-0001")&.percentile, percentile_1
    assert_equal CVEEPSS.find_by(cve_id: "CVE-1999-0002")&.percentile, percentile_2

    percentile_1 = 0.75455 # stays the same decimal place, .75
    percentile_2 = 0.64444 # stays the same decimal place, .64
    @epss_test_data = ["CVE-1999-0001,0.02345,#{percentile_1}",
                       "CVE-1999-0002,0.03456,#{percentile_2}"]

    # Because bulk insert doesn't follow timecop, we are doing this old school.
    time_before_no_op_update = Time.now
    sleep 0.002

    ingest_test_data(ingest_only_significant_percentile_updates: true)

    refute_equal CVEEPSS.find_by(cve_id: "CVE-1999-0001")&.percentile, percentile_1
    refute_equal CVEEPSS.find_by(cve_id: "CVE-1999-0002")&.percentile, percentile_2

    CVEEPSS.find_each do |cve_epss|
      # There should be no changes according to the ingest_only_significant_percentile_updates logic
      assert T.must(cve_epss.updated_at) <= time_before_no_op_update
    end
  end

  test "validate batching is safe and working as expected" do
    assert CVEEPSS.count.zero?

    batching_sequence = sequence("batching_sequence")
    CVEEPSS.expects(:insert_all).with { |argument| partial_batch_matcher(argument, 0) } .in_sequence(batching_sequence)
    CVEEPSS.expects(:insert_all).with { |argument| partial_batch_matcher(argument, 100) } .in_sequence(batching_sequence)
    CVEEPSS.expects(:insert_all).with { |argument| partial_batch_matcher(argument, 200) } .in_sequence(batching_sequence)
    ingest_test_data
  end

  def partial_batch_matcher(argument_to_verify, index_offset)
    matching = T.let(true, T::Boolean)
    argument_to_verify.each_with_index do |row, index|
      current_row = @epss_test_data[index + index_offset].split(",")
      matching = matching && (current_row == [row[:cve_id], row[:percentage], row[:percentile]])
    end
    matching
  end

  def ingest_test_data(ingestion_date: @ingest_for_date, ingest_only_significant_percentile_updates: false)
    ingestion_date_proto = Google::Protobuf::Timestamp.new
    ingestion_date_proto.from_time(ingestion_date)
    AdvisoryDB::CVEEPSSImporter.ingest_epss(source_of_ingest: "some_external_source", records_to_ingest: @epss_test_data, ingest_for_date: ingestion_date_proto.to_h, ingest_only_significant_percentile_updates: ingest_only_significant_percentile_updates)
  end
end
