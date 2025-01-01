# typed: true
# frozen_string_literal: true

class Hook::Event::DismissalRequestSecretScanningEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "dismissal requests for secret scanning alerts"

  description <<~DESC
    Secret scanning alert dismissal request was created, cancelled, or received a response.
  DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
