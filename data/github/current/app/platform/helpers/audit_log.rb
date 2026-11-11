# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class AuditLog
      # rubocop:disable Naming/ConstantName
      DeprecationNotice = {
        start_date: Date.new(2025, 10, 31),
        reason: "The GraphQL audit-log is deprecated. Please use the REST API instead.",
        superseded_by: nil,
        owner: "audit_logs"
      }
    end
  end
end
