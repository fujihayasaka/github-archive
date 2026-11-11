# typed: true
# frozen_string_literal: true

class Hook::Payload::CodeScanningAlertPayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      alert: api_serialize(:code_scanning_alert_hash, hook_event.alert, repo: hook_event.target_repository),
      ref: hook_event.ref,
      commit_oid: hook_event.commit_oid
    }
  end
end
