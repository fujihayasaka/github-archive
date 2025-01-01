# typed: true
# frozen_string_literal: true

class Hook::Event::ExemptionRequestSecretScanningEvent < Hook::Event
  include Exemptions::Hook::Event::ExemptionRequestDependency

  supports_targets *DEFAULT_TARGETS

  display_name "bypass requests for secret scanning push protections"

  # TODO: Remove note about bypass when delegated bypass for push protection is no longer in beta,
  # which may be when the secret_scanning_delegated_bypass feature flag is removed.
  description <<~DESC
    Secret scanning push protection bypass request was created, cancelled, completed, received a response, or a response was dismissed.

    Note: Delegated bypass for push protection is currently in beta and subject to change.
  DESC

  event_attr :action, :exemption_request_id, required: true
  event_attr :exemption_response_id
end
