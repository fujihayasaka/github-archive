# typed: true
# frozen_string_literal: true

module CVEEPSSImportAssertions
  extend T::Helpers
  requires_ancestor { GitHub::BasicTestCase }

  def assert_cve_epss_fully_matches(epss_test_data: @epss_test_data, ignore_ingestion_dates: false)
    assert_cve_epss_fully_matches_configurable(epss_test_data: epss_test_data, ingest_for_date: @ingest_for_date, ignore_ingestion_dates: ignore_ingestion_dates)
  end

  def assert_cve_epss_fully_matches_configurable(epss_test_data:, ingest_for_date:, ignore_ingestion_dates: false)
    assert_equal epss_test_data.count, CVEEPSS.count

    db_records = CVEEPSS.all
      .map { |cve_epss| [cve_epss.cve_id, cve_epss] }
      .to_h

    epss_test_data.each do |record|
      cve_id, percentage, percentile = record.split(",")
      cve_epss = T.must(db_records[cve_id])
      assert_equal [cve_id, percentage.to_f, percentile.to_f], [cve_epss.cve_id, cve_epss.percentage, cve_epss.percentile]
      unless ignore_ingestion_dates
        # All tests verify the current ingest_for_date unless they clear the date to match.
        # A test would only do this if it has a mix of dates in the resulting data (so delta tests).
        assert_equal @ingest_for_date.to_date, cve_epss.calculation_date
      end
    end
  end
end
