# typed: true
# frozen_string_literal: true

class Hook::Event::DismissalRequestCodeScanningEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "dismissal requests for code scanning alerts"

  description <<~DESC
    Code scanning alert dismissal request was created, or received a response (approved or rejected).

    Note: Delegated alert dismissal for code scanning is currently in public preview and subject to change.
  DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
