# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EPSSIngestionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  class TestEPSSIngestionJob < EPSSIngestionJob
    def hydro_batch_size; 10; end
  end

  test "dispatches hydro messages for every page of CSV data" do
    # This file was handmade pretty easily -- just download results and trip content to fit the test case size.
    # If you want to look at contents, just gzip -d it.
    stub_request(:get, EPSSIngestionJob::EPSS_CURRENT_CSV).to_return(body: File.read("packages/security_products/test/jobs/epss_ingestion_job_test_scores.csv.gz"))

    preamble = "#model_version:v2023.03.01,score_date:2024-07-25T00:00:00+0000"

    GlobalInstrumenter.expects(:instrument).with("epss_ingestion.issue_ingestion_batch", {
      source_of_ingest: "This is the first EPSS Ingestion Message for this ingestion run. #{preamble} Batch 1. 10 records in batch.",
      records_to_ingest: ["CVE-1999-0001,0.00383,0.73296", "CVE-1999-0002,0.02080,0.89218", "CVE-1999-0003,0.04409,0.92479", "CVE-1999-0004,0.00917,0.83061", "CVE-1999-0005,0.91963,0.98972", "CVE-1999-0006,0.03341,0.91439", "CVE-1999-0007,0.00073,0.32082", "CVE-1999-0008,0.13967,0.95731", "CVE-1999-0009,0.09014,0.94656", "CVE-1999-0010,0.00292,0.69484",],
      ingest_for_date: "2024-07-25T00:00:00+00:00".to_datetime,
    })

    GlobalInstrumenter.expects(:instrument).with("epss_ingestion.issue_ingestion_batch", {
      source_of_ingest: "#{preamble} Batch 2. 5 records in batch. This is the last EPSS Ingestion Message for this ingestion run.",
      records_to_ingest: ["CVE-1999-0011,0.01152,0.84976",    "CVE-1999-0012,0.93389,0.99121",    "CVE-1999-0013,0.00042,0.05054",    "CVE-1999-0014,0.00043,0.10065",    "CVE-1999-0015,0.00134,0.49072",],
      ingest_for_date: "2024-07-25T00:00:00+00:00".to_datetime,
    })

    TestEPSSIngestionJob.perform_now
  end

  test "Fetch errors are retried" do
    stub_request(:get, EPSSIngestionJob::EPSS_CURRENT_CSV).to_raise(OpenURI::HTTPError.new("failed to get EPSS data", StringIO.new("failed to get EPSS data")))

    assert_retry_on_error(
      EPSSIngestionJob::EPSSDownloadFailedError,
      EPSSIngestionJob,
      [],
    )
  end

  test "Invalid content fails" do
    stub_request(:get, EPSSIngestionJob::EPSS_CURRENT_CSV).to_return(body: "Not a valid gzip string")

    assert_raises(Zlib::GzipFile::Error) do
      EPSSIngestionJob.perform_now
    end
  end
end unless GitHub.single_tenant_enterprise?
