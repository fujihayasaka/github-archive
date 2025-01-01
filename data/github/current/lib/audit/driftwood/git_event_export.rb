# typed: true
# frozen_string_literal: true
#

module Audit
  module Driftwood
    # Export Git events using the Driftwood backend,
    # returns the result as a zipped JSON file
    #
    # org|business id - target's ID to export Git audit log entries from
    # start_date - A datetime variable to indicate the export's start date.
    # end_date - A datetime variable to indicate the export's end date.
    # region - The region the user/org/business belongs to

    DEFAULT_REGION = "US"

    class GitEventExport

      def initialize
        @client = GitHub.driftwood_client_v1
      end

      # Tell Driftwood to start a git event export for a given organization
      def start_org_export_v2(org_id:, token:, start_time:, end_time:, region: DEFAULT_REGION)
        @client.export_org_git_v2(
          organization_id: org_id,
          token: token,
          start_time: start_time,
          end_time: end_time,
          region: region,
        ).execute
      end

      # Tell Driftwood to start a git event export for a given business
      def start_business_export_v2(business_id:, token:, start_time:, end_time:, region: DEFAULT_REGION, feature_flags: nil)
        @client.export_business_git_v2(
          business_id: business_id,
          token: token,
          start_time: start_time,
          end_time: end_time,
          region: region,
          feature_flags: feature_flags,
        ).execute
      end

      # Query Driftwood to check whether or not a export job is complete, i.e: don't fetch results
      def check_results_v2(id:, token:, region: DEFAULT_REGION)
        resp = @client.export_fetch_results_v2(
          id: id,
          token: token,
          region: region,
          only_check_state: true,
          chunk_id: 0,
        ).execute

        { finished: resp.finished, successful: resp.successful, chunks: resp.chunks, size: resp.size, truncated: resp.truncated }
      end

      # Query Driftwood to fetch the results of an export job
      def fetch_results_v2(id:, token:, chunk:, region: DEFAULT_REGION)
        resp = @client.export_fetch_results_v2(
          id: id,
          token: token,
          region: region,
          only_check_state: false,
          chunk_id: chunk,
        ).execute

        { finished: resp.finished, successful: resp.successful, json_gzip: resp.json_gzip, chunks: resp.chunks, size: resp.size, truncated: resp.truncated }
      end

    end
  end
end
