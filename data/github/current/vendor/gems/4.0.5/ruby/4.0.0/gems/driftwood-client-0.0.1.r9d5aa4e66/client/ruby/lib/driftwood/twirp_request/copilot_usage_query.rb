# frozen_string_literal: true

require_relative "../../../lib/twirp/rpc/copilotusage/v1/copilot_usage_twirp"

module Driftwood
  module TwirpRequest
    class CopilotUsageQuery
      include Driftwood::TwirpRequest

      def build_request(options)
        Driftwood::Copilotusage::V1::CopilotUsageRecordsRequest.new(
          enterprise_id: options[:enterprise_id],
          phrase: options[:phrase],
          per_page: options[:per_page],
          after: options[:after],
          before: options[:before],
          direction: options[:direction],
        )
      end

      def client_method
        :query_copilot_usage_records
      end
    end
  end
end
