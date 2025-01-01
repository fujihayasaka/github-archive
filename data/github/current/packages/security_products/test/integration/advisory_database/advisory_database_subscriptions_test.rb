# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryDatabaseSubscriptionsTest < GitHub::TestCase
  include HydroTestHelpers

  test "creates EPSS ingestion hydro messages when instrument is called" do
    GlobalInstrumenter.instrument("epss_ingestion.issue_ingestion_batch", { source_of_ingest: "Backfill ingest", records_to_ingest: ["CVE-1999-0001,0.00383,0.73296"], ingest_for_date: "2024-07-25T00:00:00+00:00".to_datetime })

    assert_hydro_published({
      source_of_ingest: "Backfill ingest",
      records_to_ingest: ["CVE-1999-0001,0.00383,0.73296"],
      ingest_for_date: "2024-07-25T00:00:00+00:00".to_datetime,
    }, schema: "advisory_db.v0.EPSSIngest")
  end
end
