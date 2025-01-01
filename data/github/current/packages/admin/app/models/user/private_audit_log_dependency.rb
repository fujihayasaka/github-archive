# typed: true
# frozen_string_literal: true

require_relative "../../../../trust_safety/app/models/trust_safety/k_v"

module User::PrivateAuditLogDependency
  include Kernel
  extend User::RolesDependency

  class ForbiddenError < StandardError; end

  # Grant this staff user access to a target user's private audit log metadata for one hour.
  # A reason for unlocking access must be provided.
  def unlock_private_audit_logs_for(viewing, reason:)
    raise ForbiddenError.new("#{self} does not have permission to unlock private audit logs.") unless T.unsafe(self).site_admin?

    TrustSafety::KV.store.set("staff.unlock_private_audit_logs.#{T.unsafe(self).id}viewing#{viewing.id}", "true", expires: 1.hour.from_now)
    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(self)
    payload = auditing_actor.merge(
      user: viewing,
      viewing_reason: reason,
    )

    GitHub.instrument("staff.unlock_private_audit_logs", payload)
  end

  # Check whether this user currently has access to a target user's private audit log metadata.
  def can_access_private_audit_logs_for?(viewing)
    TrustSafety::KV.store.get("staff.unlock_private_audit_logs.#{T.unsafe(self).id}viewing#{viewing.id}").value { nil }
  end
end
