# typed: true
# frozen_string_literal: true

class Hook::Payload::DeploymentProtectionRulePayload < Hook::Payload
  def to_payload_hash
    payload = {
      action: "requested",
      environment: hook_event.gate.environment.name,
      event: hook_event.trigger_event,
      deployment_callback_url: hook_event.deployment_callback_url,
      deployment: api_serialize(:deployment_hash, hook_event.deployment),
      pull_requests: hook_event.pull_requests.map { |pull_request| api_serialize(:pull_request_hash, pull_request, hook: true) },
    }

    # ADR 9648: Add sha and ref from check_suite when feature flag is enabled.
    # Once fully rolled out, the feature flag will be removed and these fields
    # will always be populated per the ADR.
    if hook_event.sha_ref_feature_enabled?
      payload[:sha] = hook_event.sha if hook_event.sha.present?
      payload[:ref] = hook_event.ref if hook_event.ref.present?
    end

    payload
  end
end
