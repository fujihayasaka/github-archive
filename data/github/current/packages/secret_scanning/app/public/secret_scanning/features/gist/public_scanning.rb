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

      # not supported for proxima
      # gists have a weird relationship with proxima, and are not currently supported
      # https://github.com/github/repos/issues/3061
      return false if GitHub.multi_tenant_enterprise?

      true
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
