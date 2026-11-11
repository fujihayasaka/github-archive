# typed: true
# frozen_string_literal: true

class Hook::Event::DismissalRequestDependabotEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "dismissal requests for Dependabot alerts"

  description <<~DESC
  Dependabot alert dismissal request was created, cancelled, or received a response (approved or rejected).
DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
