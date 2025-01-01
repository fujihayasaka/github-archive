# typed: true
# frozen_string_literal: true

module AdvisoryDB::CVEEPSSImporter

  # ingest_epss is common functionality that is split into a separate file.
  # Dotcom uses this code for its own ingestion from the EPSS data source, and GHES/proxima reuses ingestion logic.
  #   - source_of_ingest: String, the source of the data being ingested. This is used for logging purposes.
  #   - records_to_ingest: Array of Strings, where each string is a comma-separated list of values to be ingested.
  #        format of records to ingest is <cve_id>,<percentage>,<percentile
  #   - ingest_for_date: Hash of a protobuf timestamp
  #
  # The format for some params most closely matches dotcom, because dotcom will be doing bulk import the most often.
  # Sticking with CSV means this code closely matches the current format of EPSS's data.
  sig { params(source_of_ingest: String, records_to_ingest: T::Array[String], ingest_for_date: Hash, ingest_only_significant_percentile_updates: T::Boolean).void }
  def self.ingest_epss(source_of_ingest:, records_to_ingest:, ingest_for_date:, ingest_only_significant_percentile_updates: false)
    CVEEPSS.with_read do
      GitHub.logger.info("Beginning processing an EPSS import. Source of import is: #{source_of_ingest} and number of records being processed is #{records_to_ingest.count}")
      group_number = 0
      # We pick a batch of 100 based on guidance around max batch sizes found at https://thehub.github.com/epd/engineering/dev-practicals/mysql/query-guidelines/#guidelines
      records_to_ingest.in_groups_of(100, false) do |records|
        group_number += 1
        GitHub.logger.info("Starting a batch of EPSS records. Group number #{group_number}")
        CVEEPSS.throttle do
          # This was originally written with a plan to use upsert_all, instead we are doing separate read / write stages to avoid using upsert_all.
          # This still assumes there are not multiple sources engaging in R/W at the same time and that the processor is serialized.
          incoming_cve_epss_split_records = records.map { |r| r.split(",") }
          matching_db_records = CVEEPSS
            .where(cve_id: incoming_cve_epss_split_records.map(&:first)) # all CVEEPSS that match CVE ID, which is :first
            .map { |cve_epss| [cve_epss.cve_id, cve_epss] }
            .to_h

          insert_me = []
          update_me = []
          incoming_cve_epss_split_records.each do |cve_id, new_percentage, new_percentile|
            if matching_db_records.key? cve_id
              cve_epss = T.must(matching_db_records[cve_id])

              # In theory, we could apply this same logic to GHES and proxima, but I wanted to preserve the semantic
              # intent of their syncs: They should not be excluding any data coming from dotcom, and so shouldn't be
              # doing this check themselves, instead just ingesting all changed data.
              if  (ingest_only_significant_percentile_updates &&
                    (cve_epss.percentage != new_percentage.to_f ||
                      is_change_significant(cve_epss.percentile, new_percentile.to_f))) ||
                  (!ingest_only_significant_percentile_updates &&
                    [cve_epss.percentage, cve_epss.percentile] != [new_percentage.to_f, new_percentile.to_f])
                cve_epss.percentage = new_percentage
                cve_epss.percentile = new_percentile

                # Sometimes the EPSS score's CVE-ID does not have a matching ADB vulnerability entry, details: https://github.com/github/dependabot-updates/issues/8462
                if cve_epss.vulnerability.present?
                  T.must(cve_epss.vulnerability).instrument_dependabot_alerts_upstream_change(event: :update, changes: ["epss"])
                end
                update_me << cve_epss
              end
            else
              insert_me << { cve_id: cve_id, percentage: new_percentage, percentile: new_percentile }
            end
          end

          (insert_me + update_me).each { |r| r[:calculation_date] = Google::Protobuf::Timestamp.new(ingest_for_date).to_time.utc }

          CVEEPSS.with_write do
            CVEEPSS.insert_all(insert_me) unless insert_me.empty?
            update_me.each(&:save!)
          end

          unless GitHub.single_tenant_enterprise?
            Vulnerability.where(cve_id: insert_me.map { |i| i[:cve_id] }).each do |vuln|
              vuln.synchronize_search_index
            end
          end
        end
      end

      GitHub.logger.info("Finishing processing an EPSS import. Source of import is: #{source_of_ingest} and number of records being processed is #{records_to_ingest.count}")
    end
  end

  sig { params(old_decimal_value: BigDecimal, new_decimal_value: Float).returns(T::Boolean) }
  def self.is_change_significant(old_decimal_value, new_decimal_value)
    old_decimal_value.round(2) != new_decimal_value.round(2)
  end
end
