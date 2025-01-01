# typed: true
# frozen_string_literal: true

class Hook::Payload::DeploymentProtectionRulePayload < Hook::Payload

  def to_payload_hash
    {
      action: "requested",
      environment: hook_event.gate.environment.name,
      event: hook_event.trigger_event,
      deployment_callback_url: hook_event.deployment_callback_url,
      deployment: api_serialize(:deployment_hash, hook_event.deployment),
      pull_requests: hook_event.pull_requests.map { |pull_request| api_serialize(:pull_request_hash, pull_request, hook: true) },
    }
  end
end
