# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Gist
  class PublicScanning
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(gist: Gist).void }
    def initialize(gist)
      @gist = gist
    end

    # Indicates whether the Public Scanning feature as a whole is available to the current gist
    sig { returns(T::Boolean) }
    def feature_available?
      # global config check
      # should be on by default for dotcom and needs to be enabled for enterprise
      return false unless GitHub.configuration_secret_scanning_enabled?

      # not supported on GHES
      return false if GitHub.enterprise?

      # only supported for public gists
      return true if @gist.public?

      # There's not really a concept of "private" gists, they are considered "secret gists"
      # We're also beginning to evaluate whether to scan these gists, and to treat them as "public",
      # in that we'd notify partners of matches within them
      return true if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SCAN_PRIVATE_GISTS].enabled?(@gist.owner)

      false
    end

    # Indicates whether Public Scanning is enabled for the current gist
    sig { returns(T::Boolean) }
    def enabled?
      # base feature must be available
      return false unless self.feature_available?

      true
    end
  end
end
