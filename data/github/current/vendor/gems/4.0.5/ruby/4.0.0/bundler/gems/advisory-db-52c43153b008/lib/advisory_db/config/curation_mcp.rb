# frozen_string_literal: true

module AdvisoryDB
  module Config
    module CurationMCP
      def self.server_base_url
        ENV.fetch("CURATION_MCP_SERVER_BASE_URL", "")
      end

      def self.chat_disabled?
        ENV.fetch("CURATION_MCP_CHAT_DISABLED", "false") == "true"
      end
    end
  end
end
