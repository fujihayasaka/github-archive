# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module AdvisoryDB
      class EPSSIngestionProcessor < BaseProcessor
        options.update(
          start_from_beginning: false,
        )

        DEFAULT_GROUP_ID = "epss_ingestion"
        DEFAULT_SUBSCRIBE_TO = /advisory_db.v0.EPSSIngest\Z/
        STATS_NAMESPACE = "advisory_db_processor.epss_ingestion"

        private

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "cp1-iad.ingest.advisory_db.v0.EPSSIngest.DeadLetter"
        end

        def process_message(message)
          start_time = GitHub::Dogstats.monotonic_time
          tags = []
          payload = message.value
          success = false
          result = "error"

          begin
            ingest_epss(payload)
            success = true
          ensure
            tags << "success:#{success}"
            GitHub.dogstats.timing_since("advisory_db.epss_ingest.process_time", start_time, tags: tags)
          end
        end

        def ingest_epss(payload)
          GitHub.logger.info("Beginning processing an EPSSIngestMessage. Message being processed is: #{payload[:source_of_ingest]} and number of records being processed is #{payload[:records_to_ingest].count}")
          group_number = 0
          # We pick a batch of 100 based on guidance around max batch sizes found at https://thehub.github.com/epd/engineering/dev-practicals/mysql/query-guidelines/#guidelines
          payload[:records_to_ingest].in_groups_of(100, false) do |records|
            group_number += 1
            if !GitHub.flipper[:advisory_db_processor_epss_ingestion].enabled?
              GitHub.logger.info("Skipping a batch of EPSS ingestion due to FF being disabled. Group number #{group_number}")
            else
              GitHub.logger.info("Starting a batch of EPSS ingestion. Group number #{group_number}")
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
                incoming_cve_epss_split_records.each do |cve_id, percentage, percentile|
                  if matching_db_records.key? cve_id
                    cve_epss = T.must(matching_db_records[cve_id])
                    if [cve_epss.percentage, cve_epss.percentile] != [percentage.to_f, percentile.to_f]
                      cve_epss.percentage = percentage
                      cve_epss.percentile = percentile
                      update_me << cve_epss
                    end
                  else
                    insert_me << { cve_id: cve_id, percentage: percentage, percentile: percentile }
                  end
                end

                (insert_me + update_me).each { |r| r[:calculation_date] = Google::Protobuf::Timestamp.new(payload[:ingest_for_date]).to_time.utc }

                with_write do
                  CVEEPSS.insert_all(insert_me) unless insert_me.empty?
                  update_me.each(&:save!)
                end
              end
            end
          end

          GitHub.logger.info("Finishing processing an EPSSIngestMessage. Message being processed is: #{payload[:source_of_ingest]} and number of records being processed is #{payload[:records_to_ingest].count}")
        end
      end
    end
  end
end
