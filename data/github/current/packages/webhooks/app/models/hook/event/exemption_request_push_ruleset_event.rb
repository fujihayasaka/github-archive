# typed: true
# frozen_string_literal: true

class Hook::Event::ExemptionRequestPushRulesetEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "bypass requests for push rulesets"

  description <<-DESC
    Push ruleset bypass request was created, cancelled, completed, received a response, or a response was dismissed.
  DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
