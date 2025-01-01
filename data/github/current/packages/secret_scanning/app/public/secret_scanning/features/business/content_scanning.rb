# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Repository level enablement for Content Scanning
  class ContentScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @public_scanning = T.let(SecretScanning::Features::Business::PublicScanning.new(@business), SecretScanning::Features::Business::PublicScanning)
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      if GitHub.enterprise?
        return false unless GitHub.secret_scanning_for_all_content_types_enabled?
      end

      # feature is available on public repos if public scanning is enabled, or if token scanning is enabled
      @public_scanning.enabled? || @token_scanning.enabled?
    end

    # Indicate whether the feature is enabled for this repository
    sig { returns(T::Boolean) }
    def enabled?
      # Always enabled if available
      self.feature_available?
    end
  end
end
