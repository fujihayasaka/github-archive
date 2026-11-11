# typed: true
# frozen_string_literal: true

module Settings
  class AuditLogEntry < ::AuditLogEntry
    ALLOWED_METADATA_KEYS = %w(actor user repo created_at note)
    SELF_ALLOWED_METADATA_KEYS = ALLOWED_METADATA_KEYS + %w(actor_ip)
  end
end
