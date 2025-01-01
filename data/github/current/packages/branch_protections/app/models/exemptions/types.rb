# typed: false
# frozen_string_literal: true

module Exemptions
  class Types

    ExemptionRequestDataHash = T.type_alias do
      {
        type: String,
        data: T::Array[T::Hash[Symbol, T.untyped]]
      }
    end

    ExemptionRequestEvent = T.type_alias do
      T.any(
        ::Hook::Event::ExemptionRequestPushRulesetEvent,
        ::Hook::Event::ExemptionRequestSecretScanningEvent
      )
    end

    ExemptionRequestPayload = T.type_alias do
      T.any(
        ::Hook::Payload::ExemptionRequestPushRulesetPayload,
        ::Hook::Payload::ExemptionRequestSecretScanningPayload
      )
    end
  end
end
