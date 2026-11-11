# typed: true
# frozen_string_literal: true

class Hook::Payload::ExemptionRequestPushRulesetPayload < Hook::Payload
  include Exemptions::Hook::Payload::ExemptionRequestDependency
end
