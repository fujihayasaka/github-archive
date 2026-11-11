# typed: true
#frozen_string_literal: true

module GitHub
  module Config
    module AuditLogCuratorConfig
      def audit_log_es_curator_enabled?
        @audit_log_es_curator_enabled = GitHub.single_business_environment?
      end
      attr_accessor :audit_log_es_curator_enabled
    end
  end
  extend Config::AuditLogCuratorConfig
end
