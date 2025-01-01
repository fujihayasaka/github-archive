# frozen_string_literal: true
# typed: strict

module Vexi
  # GetFeatureFlagResponse is the response returned by the GetFeatureFlag method.
  class GetFeatureFlagResponse < GetEntityResponse
    extend T::Sig
    extend T::Helpers

    sig { returns(T.nilable(FeatureFlag)) }
    attr_reader :feature_flag

    sig { params(name: String, feature_flag: T.nilable(FeatureFlag), error: T.nilable(StandardError)).void }
    def initialize(name: "", feature_flag: nil, error: nil); end
  end
end
