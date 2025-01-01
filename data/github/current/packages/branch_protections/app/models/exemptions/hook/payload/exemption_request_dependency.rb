# typed: true
# frozen_string_literal: true

module Exemptions::Hook::Payload::ExemptionRequestDependency
  extend T::Helpers

  requires_ancestor { ::Hook::Payload }

  def to_payload_hash
    T.bind(self, Exemptions::Types::ExemptionRequestPayload)

    {}.tap do |payload|
      payload[:action] = hook_event.action
      payload[:exemption_request] = Api::Serializer.serialize(:exemption_request_hash, hook_event.exemption_request)
      payload[:exemption_response] = Api::Serializer.serialize(:exemption_response_hash, hook_event.exemption_response) if hook_event.exemption_response.present?
    end
  end
end
