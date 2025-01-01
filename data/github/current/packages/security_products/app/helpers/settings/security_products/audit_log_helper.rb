# typed: true
# frozen_string_literal: true

module Settings
  module SecurityProducts
    module AuditLogHelper
      extend T::Sig

      # Load JSON file and parse it
      file_path = Rails.root.join("config", "code_security_configuration_failures.json")
      ENABLEMENT_FAILURES_MAP = T.let(JSON.parse(File.read(file_path))["failures"], T::Hash[String, T.untyped])

      sig { params(failure_reason: T.nilable(String)).returns(T.nilable(String)) }
      def audit_log_message(failure_reason)
        return nil unless failure_reason

        failure = ENABLEMENT_FAILURES_MAP[failure_reason]
        return failure["audit_log_message"] if failure && failure["audit_log_allowed"]

        "Failed to enable."
      end
    end
  end
end
