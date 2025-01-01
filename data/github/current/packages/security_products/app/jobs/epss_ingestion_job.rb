# typed: true
# frozen_string_literal: true

require "open-uri"
require "csv"
require "zlib"

# This job will parse an EPSS file and send hydro messages with the data chopped up to be processed by aqueduct jobs.
# We use this layer to parse the incoming file to quarterback the file (~ 13MB uncompressed) to smaller chunks without
# using any permanent storage.
class EPSSIngestionJob < ApplicationJob
  class EPSSDownloadFailedError < StandardError; end

  EPSS_CURRENT_CSV = "https://epss.cyentia.com/epss_scores-current.csv.gz"

  queue_as :epss_ingestion
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on EPSSDownloadFailedError, wait: :polynomially_longer, attempts: 3

  sig { returns(T.untyped) }
  def perform
    csv_scores = T.let(nil, T.nilable(String))
    download_response = T.let(nil, T.nilable(IO))
    # We wrap StandardErrors because there's a lot that can go wrong in network access and we know we need to retry failures in those cases.
    # For errors we don't expect to be retried, we raise.
    begin
      download_response = URI.open(EPSS_CURRENT_CSV)
    rescue StandardError => e # rubocop:disable Lint/GenericRescue
      GitHub.logger.info("EPSS Download Failed with error during 'URI.open' => #{e}")
      raise EPSSDownloadFailedError, "Failed to download EPSS scores: #{e}"
    end

    raise EPSSDownloadFailedError, "URI.open returned nil result." if download_response.nil?

    current_epss_scores = nil
    begin
      current_epss_scores = T.must(download_response).read
    rescue StandardError => e # rubocop:disable Lint/GenericRescue
      GitHub.logger.info("EPSS Download Failed with error during '.read' of URI.open'ed instance => #{e}")
      raise EPSSDownloadFailedError, "Failed to download EPSS scores: #{e}"
    end

    # We use zcat here because standard decompression doesn't support zcat and only produces the first line of decompressed output.
    # If this fails, we don't really need retries or anything, it means the data is likely malformed.
    csv_scores = T.let(T.unsafe(Zlib::GzipReader).zcat(StringIO.new(current_epss_scores)), String)

    # Data looks like this:
    # #model_version:v2023.03.01,score_date:2024-03-17T00:00:00+0000
    # cve,epss,percentile
    # CVE-1999-0001,0.00383,0.72449
    # CVE-1999-0002,0.02080,0.88805
    # CVE-1999-0003,0.04409,0.92181
    # CVE-1999-0004,0.00917,0.82459

    scores = csv_scores.split("\n")

    # Grab the first two lines
    preamble, column_headers = scores[..1]

    # We're doing basic string parsing here and getting a null ref is tolerable and unlikely.
    # #model_version:v2023.03.01,score_date:2024-03-17T00:00:00+0000
    model_version = T.must(T.must(preamble).split(",")[0]).split(":")[1]
    score_date = T.must(T.must(T.must(preamble).split(",")[1]).split(":")[1]).to_datetime

    raise "Preamble line is not correctly formatted. Line found was: #{preamble}" unless T.must(model_version).start_with?("v2023.03") && score_date

    # Verify column headers still match expectations. It is possible they could have additive data, which is not the end of the world.
    raise "Column headers do not match" unless column_headers == "cve,epss,percentile" || T.must(column_headers).start_with?("cve,epss,percentile,")

    scores = scores[2..]

    batch_number = 1
    running_total = 0

    T.must(scores).in_groups_of(hydro_batch_size, false) do |batch|
      first_message_header = running_total.zero? ? "This is the first EPSS Ingestion Message for this ingestion run. " : ""
      second_message_footer = (running_total + batch.count >= T.must(scores).size) ? " This is the last EPSS Ingestion Message for this ingestion run." : ""
      issue_epss_message(batch, "#{first_message_header}#{preamble} Batch #{batch_number}. #{batch.count} records in batch.#{second_message_footer}", score_date)
      batch_number = batch_number + 1
      running_total = running_total + batch.count
    end

    nil
  end

  private

  sig { params(records: T::Array[String], reason: String, ingest_for_date: DateTime).returns(T.untyped) }
  def issue_epss_message(records, reason, ingest_for_date)
    message = {
      source_of_ingest: reason,
      records_to_ingest: records,
      ingest_for_date: ingest_for_date,
    }

    GitHub.logger.info("EPSS Ingestion Job is issuing an ingestion batch. #{message}")
    GlobalInstrumenter.instrument("epss_ingestion.issue_ingestion_batch", message)
  end

  def hydro_batch_size
    # We want to override this in a test.
    # We know this size generally represents significantly < 1MB of data.
    # At the time of this writing, we get about 250K records from the ingest, so this is one out of ~50 messages.
    # It's up to the receiver to follow best practices with DB interaction, this job only queues following best practices for hydro.
    5000
  end
end
