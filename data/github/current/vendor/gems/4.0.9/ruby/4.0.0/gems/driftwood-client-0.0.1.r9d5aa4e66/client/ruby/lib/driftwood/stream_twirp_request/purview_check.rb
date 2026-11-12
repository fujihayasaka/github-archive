# frozen_string_literal: true

require_relative "../../../lib/twirp/rpc/auditlog/v1/audit_log_twirp"

module Driftwood
  module StreamTwirpRequest
    class PurviewCheck
      include Driftwood::StreamTwirpRequest

      def build_request(options)
        klass = get_request_class("StreamPurviewCheck")

        klass.new(
          subject_id: options[:subject_id],
          subject_type: options[:subject_type],
          entra_tenant_id: options[:entra_tenant_id],
        )
      end

      def client_method
        :stream_purview_check
      end
    end
  end
end
