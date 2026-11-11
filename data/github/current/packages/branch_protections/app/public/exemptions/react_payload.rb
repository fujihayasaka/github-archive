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
          rules_bypass_requests_filter_bar: source.feature_enabled_for_source?(:rules_bypass_requests_filter_bar),
          secret_scanning_requests_filter_bar: source.feature_enabled_for_source?(:secret_scanning_requests_filter_bar),
          code_scanning_requests_filter_bar: source.feature_enabled_for_source?(:code_scanning_requests_filter_bar),
          security_products_filter_bar_afd: source.feature_enabled_for_source?(:security_products_filter_bar_afd),
          dependabot_requests_filter_bar: source.feature_enabled_for_source?(:dependabot_requests_filter_bar),
          license_compliance_requests_filter_bar: source.feature_enabled_for_source?(:license_compliance_requests_filter_bar),
        },
        is_stafftools:,
        request_type:,
        base_avatar_url: GitHub.alambic_avatar_url,
      }
    end

    ### TODO
  end
end
