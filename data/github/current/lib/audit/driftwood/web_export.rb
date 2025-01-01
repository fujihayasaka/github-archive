# typed: true
# frozen_string_literal: true
#

module Audit
  module Driftwood
    class WebExport
      def initialize
        @client = GitHub.driftwood_client_v1
      end

      # Tell Driftwood to start a web event export for a given organization, user or business
      def export_start_web(subject_id:, subject_type:, key_id:, format_type:, export_id:, encrypted_phrase:, disclose_ip_address:, feature_flags: [], non_sso_org_ids: [])
        @client.export_start_web(
          subject_id: subject_id,
          subject_type: subject_type,
          key_id: key_id,
          format_type: format_type,
          export_id: export_id,
          encrypted_phrase: encrypted_phrase,
          disclose_ip_address: disclose_ip_address,
          feature_flags: feature_flags,
          non_sso_org_ids: non_sso_org_ids,
        ).execute
      end

      # Query Driftwood to check whether or not a export job is complete, i.e: don't fetch results
      def check_web_status(subject_id:, subject_type:, format_type:, export_id:, feature_flags: [])
        resp = @client.export_check_web_status(
          subject_id: subject_id,
          subject_type: subject_type,
          format_type: format_type,
          export_id: export_id,
          feature_flags: feature_flags,
        ).execute

        { chunks: resp.chunks, size: resp.size, status: resp.status, truncated: resp.truncated }
      end

      # Query Driftwood to fetch the results of an export job
      def fetch_web_result(subject_id:, subject_type:, format_type:, export_id:, chunk_idx:, feature_flags: [])
        resp = @client.export_fetch_web_result(
          subject_id: subject_id,
          subject_type: subject_type,
          format_type: format_type,
          export_id: export_id,
          chunk_idx: chunk_idx,
          feature_flags: feature_flags,
        ).execute

        { chunk_data: resp.chunk_data }
      end

    end
  end
end
