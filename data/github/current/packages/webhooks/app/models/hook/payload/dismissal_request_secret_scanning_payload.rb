# typed: true
# frozen_string_literal: true

class Hook::Payload::DismissalRequestSecretScanningPayload < Hook::Payload
  include Exemptions::Hook::Payload::ExemptionRequestDependency
end
