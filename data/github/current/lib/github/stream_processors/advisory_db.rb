# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module AdvisoryDB
      autoload :CVERequestResponseProcessor, "github/stream_processors/advisory_db/cve_request_response_processor"
      autoload :SubmitAdvisoryProcessor, "github/stream_processors/advisory_db/submit_advisory_processor"
      autoload :EPSSIngestionProcessor, "github/stream_processors/advisory_db/epss_ingestion_processor"
    end
  end
end
