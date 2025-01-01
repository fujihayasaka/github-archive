# typed: true
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
        ::Hook::Event::ExemptionRequestSecretScanningEvent,
        ::Hook::Event::DismissalRequestCodeScanningEvent,
        ::Hook::Event::DismissalRequestSecretScanningEvent,
      )
    end

    ExemptionRequestPayload = T.type_alias do
      T.any(
        ::Hook::Payload::ExemptionRequestPushRulesetPayload,
        ::Hook::Payload::ExemptionRequestSecretScanningPayload,
        ::Hook::Payload::DismissalRequestCodeScanningPayload,
        ::Hook::Payload::DismissalRequestSecretScanningPayload,
      )
    end
  end
end
