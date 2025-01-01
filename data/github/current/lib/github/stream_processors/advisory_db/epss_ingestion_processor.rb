# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module AdvisoryDB
      class EPSSIngestionProcessor < SingleMessageProcessor
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
            ::AdvisoryDB::CVEEPSSImporter.ingest_epss(
              source_of_ingest: payload[:source_of_ingest],
              records_to_ingest: payload[:records_to_ingest],
              ingest_for_date: payload[:ingest_for_date],
              ingest_only_significant_percentile_updates: true)
            success = true
          ensure
            tags << "success:#{success}"
            GitHub.dogstats.timing_since("advisory_db.epss_ingest.process_time", start_time, tags: tags)
          end
        end
      end
    end
  end
end
