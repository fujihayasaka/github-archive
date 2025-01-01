# typed: true
# frozen_string_literal: true

class Hook::Payload::ExemptionRequestSecretScanningPayload < Hook::Payload
  include Exemptions::Hook::Payload::ExemptionRequestDependency
end
