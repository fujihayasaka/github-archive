# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubPreconditionFailedError < StandardError
    extend T::Sig
  end
end
