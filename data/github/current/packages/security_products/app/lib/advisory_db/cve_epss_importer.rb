# typed: true
# frozen_string_literal: true

module AdvisoryDB::CVEEPSSImporter

  # Process records in batches of 50 to keep batch processing times low
  BATCH_SIZE = 50

  # Allow up to 3 attempts to wait for replication lag to clear
  MAX_THROTTLER_RETRIES = 3

  # ingest_epss is common functionality that is split into a separate file.
  # Dotcom uses this code for its own ingestion from the EPSS data source, and GHES/proxima reuses ingestion logic.
  #   - source_of_ingest: String, the source of the data being ingested. This is used for logging purposes.
  #   - records_to_ingest: Array of Strings, where each string is a comma-separated list of values to be ingested.
  #        format of records to ingest is <cve_id>,<percentage>,<percentile
  #   - ingest_for_date: Hash of a protobuf timestamp
  #
  # The format for some params most closely matches dotcom, because dotcom will be doing bulk import the most often.
  # Sticking with CSV means this code closely matches the current format of EPSS's data.
  sig do
    params(
      source_of_ingest: String,
      records_to_ingest: T::Array[String],
      ingest_for_date: Hash,
      ingest_only_significant_percentile_updates: T::Boolean,
      block: T.nilable(T.proc.void)
    ).void
  end
  def self.ingest_epss(source_of_ingest:, records_to_ingest:, ingest_for_date:, ingest_only_significant_percentile_updates: false, &block)
    GitHub.logger.info("Beginning processing an EPSS import. Source of import is: #{source_of_ingest} and number of records being processed is #{records_to_ingest.count}")
    group_number = 0

    ingest_for_date = Google::Protobuf::Timestamp.new(ingest_for_date).to_time.utc

    records_to_ingest.in_groups_of(BATCH_SIZE, false) do |records|
      group_number += 1
      GitHub.logger.info("Starting a batch of EPSS records. Group number #{group_number}")
      CVEEPSS.throttle_with_retry(max_retry_count: MAX_THROTTLER_RETRIES) do
        GitHub.dogstats.distribution_time("advisory_db.epss_ingest.processor.batch.dist.time") do
          ingest_epss_batch(records:, ingest_for_date:, ingest_only_significant_percentile_updates:)
        end
        yield if block_given?
      end
    end

    GitHub.logger.info("Finishing processing an EPSS import. Source of import is: #{source_of_ingest} and number of records being processed is #{records_to_ingest.count}")
  end

  sig { params(records: T::Array[String], ingest_for_date: Time, ingest_only_significant_percentile_updates: T::Boolean).void }
  def self.ingest_epss_batch(records:, ingest_for_date:, ingest_only_significant_percentile_updates: false)
    # This was originally written with a plan to use upsert_all, instead we are doing separate read / write stages to avoid using upsert_all.
    # This still assumes there are not multiple sources engaging in R/W at the same time and that the processor is serialized.

    # Parse incoming CSV records into structured data
    parsed_epss_records = parse_csv_records(records)
    parsed_epss_records.each { |data| data[:calculation_date] = ingest_for_date }

    # Fetch any existing CVEPSS records that match the incoming batch
    matching_db_records = CVEEPSS.with_read do
      # all CVEEPSS that match the batch CVE IDs
      CVEEPSS.where(cve_id: parsed_epss_records.map { |r| r[:cve_id] })
        # preload vulnerability association to avoid n+1s calling instrumentation
        .includes(:vulnerability)
        .index_by { |cve_epss| cve_epss.cve_id }
    end

    # Split incoming records into inserts and updates
    epss_records_for_insert, epss_records_for_update = parsed_epss_records.partition do |cve_data|
      !matching_db_records.key?(cve_data[:cve_id])
    end

    # Filter and prepare DB records for update
    db_records_for_update = epss_records_for_update.filter_map do |epss_data|
      db_record = T.must(matching_db_records[epss_data[:cve_id]])
      next unless should_update_epss_record?(db_record, epss_data, ingest_only_significant_percentile_updates)

      db_record.assign_attributes(**epss_data)
      db_record
    end

    # Write changes to the DB
    CVEEPSS.with_write do
      CVEEPSS.transaction do
        CVEEPSS.insert_all(epss_records_for_insert) unless epss_records_for_insert.empty?
        db_records_for_update.each(&:save!)
      end
    end

    GitHub.dogstats.count("advisory_db.epss_ingest.processor.records_inserted", epss_records_for_insert.size)
    GitHub.dogstats.count("advisory_db.epss_ingest.processor.records_updated", db_records_for_update.size)

    # Perform post-update actions
    Vulnerability.with_read do
      db_records_for_update.each do |db_record|
        # Sometimes the EPSS score's CVE-ID does not have a matching ADB vulnerability entry,
        # details: https://github.com/github/dependabot-updates/issues/8462
        db_record.vulnerability&.instrument_dependabot_alerts_upstream_change(event: :update, changes: ["epss"])
      end

      unless GitHub.single_tenant_enterprise?
        Vulnerability.where(cve_id: epss_records_for_insert.map { |i| i[:cve_id] }).each do |vuln|
          vuln.synchronize_search_index
        end
      end
    end
  end

  sig { params(raw_csv_records: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.parse_csv_records(raw_csv_records)
    raw_csv_records.map do |r|
      cve_id, percentage, percentile = r.split(",").map(&:strip)
      {
        cve_id: cve_id,
        percentage: percentage.to_f,
        percentile: percentile.to_f,
      }
    end
  end

  sig do
    params(
      db_record: CVEEPSS,
      new_data: T::Hash[Symbol, T.untyped],
      ingest_only_significant_percentile_updates: T::Boolean
    ).returns(T::Boolean)
  end
  def self.should_update_epss_record?(db_record, new_data, ingest_only_significant_percentile_updates)
    # always update if the percentage has changed
    return true if db_record.percentage != new_data[:percentage]
    # below here we know the percentage is the same

    # skip updates if both the percentage and percentile are the same
    return false if db_record.percentile == new_data[:percentile]
    # below here we know the percentage is the same and the percentile is different

    # update unless we are limiting updates to significant percentile changes
    return true unless ingest_only_significant_percentile_updates

    # update if the change in percentile is significant
    is_change_significant(db_record.percentile, new_data[:percentile])
  end

  sig { params(old_decimal_value: BigDecimal, new_decimal_value: Float).returns(T::Boolean) }
  def self.is_change_significant(old_decimal_value, new_decimal_value)
    old_decimal_value.round(2) != new_decimal_value.round(2)
  end
end
