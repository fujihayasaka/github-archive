# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::User
  class TokenScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper
    SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_repos_enable"

    sig { params(user: User).void }
    def initialize(user)
      @user = user
      @ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(@user)
    end

    # Indicate whether the feature is enabled for this user-owned repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless GitHub.configuration_secret_scanning_enabled?
      return true if available_for_private_repos?

      false
    end

    # Indicates whether Token Scanning is enabled for the current user
    def enabled?
      self.feature_available?
    end

    # Indicates whether private repo enablement is available for GHEC enterprise managed users / GHES users
    sig { returns(T::Boolean) }
    def available_for_private_repos?
      @ghas_for_users.feature_available?
    end

    sig { returns(T::Boolean) }
    def can_enable_for_new_repos?
      available_for_private_repos?
    end

    def enable_secret_scanning_for_new_repos(actor:)
      @user.config.enable(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    def disable_secret_scanning_for_new_repos(actor:)
      @user.config.disable(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    def secret_scanning_enabled_for_new_repos?
      return false unless self.feature_available?
      @user.config.enabled?(SECRET_SCANNING_NEW_REPOS_KEY)
    end
  end
end
