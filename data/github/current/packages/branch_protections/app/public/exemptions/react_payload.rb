# typed: strict
# frozen_string_literal: true

module Exemptions
  module ReactPayload

    sig do
      params(source: RuleEngine::Types::RuleSource, request_type: String, is_stafftools: T::Boolean).returns({
        enabled_features: T::Hash[Symbol, T::Boolean],
        is_stafftools: T::Boolean,
        request_type: String,
        base_avatar_url: String,
      })
    end
    def self.app_payload(source, request_type, is_stafftools: false)
      {
        enabled_features: {
          delegated_bypass_banner_enhancements: source.delegated_bypass_banner_enhancements?,
        },
        is_stafftools:,
        request_type:,
        base_avatar_url: GitHub.alambic_avatar_url,
      }
    end

    ### TODO
  end
end
