# typed: true
# frozen_string_literal: true

class Hook::Event::ExemptionRequestPushRulesetEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "bypass requests for push rulesets"

  # TODO: Remove note about delegated bypass for push rules being in beta when it is no longer in beta,
  # which may be when the push_ruleset_delegated_bypass feature flag is removed and
  # the push_ruleset_exemption_request_webhooks feature flag is removed
  description <<-DESC
    Push ruleset bypass request was created, cancelled, completed, received a response, or a response was dismissed.

    Note: Delegated bypass for push rules is currently in beta and subject to change.
  DESC

  feature_flag :push_ruleset_exemption_request_webhooks, ui_note: false

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
