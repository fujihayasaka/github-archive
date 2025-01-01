# typed: true
# frozen_string_literal: true

module AuditLogHelper
  def driftwood_ade_query?(user = nil)
    return false unless user
    GitHub.driftwood_enabled? && !GitHub.enterprise?
  end
end
