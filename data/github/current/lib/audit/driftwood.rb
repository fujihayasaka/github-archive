# typed: true
# frozen_string_literal: true

module Audit
  module Driftwood
    autoload :GitEventExport, "audit/driftwood/git_event_export"
    autoload :Query, "audit/driftwood/query"
    autoload :WebExport, "audit/driftwood/web_export"
    autoload :GitExport, "audit/driftwood/git_export"
    autoload :AsyncQuery, "audit/driftwood/async_query"

    QUERY_TIMEOUT = 8

    def self.get_audit_entry(document_id)
      response = GitHub.driftwood_client_v1.get_audit_entry(id: document_id).execute
      response.results.try(:first)
    end
  end
end
