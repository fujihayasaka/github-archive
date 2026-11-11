# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module HttpFluentbitConfig
      def http_fluentbit_enabled?
        return @http_fluentbit_enabled if defined?(@http_fluentbit_enabled)
        @http_fluentbit_enabled = !GitHub.http_fluentbit_server.nil?
      end
      attr_accessor :http_fluentbit_enabled

      def http_fluentbit_server
        GitHub.environment.fetch("AUDIT_FORWARD_HTTP_FLUENTBIT_SERVER", @http_fluentbit_server)
      end
      attr_writer :http_fluentbit_server
    end
  end
  extend Config::HttpFluentbitConfig
end
