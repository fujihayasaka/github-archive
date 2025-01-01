# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::User
  # Owner level enablement for Issue Scanning
  class ContentScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(user: User).void }
    def initialize(user)
      @user = user
      @public_scanning = T.let(SecretScanning::Features::User::PublicScanning.new(@user), SecretScanning::Features::User::PublicScanning)
      @token_scanning = T.let(SecretScanning::Features::User::TokenScanning.new(@user), SecretScanning::Features::User::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      if GitHub.enterprise?
        return false unless GitHub.secret_scanning_for_all_content_types_enabled?
      end

      # feature is available on a user if public scanning is available, or if token scanning is enabled
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
