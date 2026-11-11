# typed: strict
# frozen_string_literal: true

# Groups core features (which determine Quick Setup state) with their companion features
# (which follow that state with individual defaults).
class SecurityProductsEnablement::QuickSetupService::FeatureGroup < T::Struct
  const :core_features, T::Array[Symbol]
  const :companion_features, T::Array[SecurityProductsEnablement::QuickSetupService::CompanionFeature]

  sig do
    params(
      core_features: T::Array[Symbol],
      companion_features: T::Array[SecurityProductsEnablement::QuickSetupService::CompanionFeature]
    ).returns(SecurityProductsEnablement::QuickSetupService::FeatureGroup)
  end
  def self.create(core_features:, companion_features:)
    new(core_features: core_features.freeze, companion_features: companion_features.freeze).freeze
  end
end
