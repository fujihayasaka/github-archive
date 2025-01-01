# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Business
  class TokenScanning
    include SecretScanning::Features::FeatureFlagHelper
    SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_business_repos_enable"

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
    end

    # Indicates whether the Token Scanning feature as a whole is available to the current business
    sig { returns(T::Boolean) }
    def feature_available?
      # global config check
      # should be on by default for dotcom and needs to be enabled for enterprise
      return false unless GitHub.configuration_secret_scanning_enabled?

      # billing/license check (applies to both GHES and dotcom)
      return true if @business.advanced_security_purchased?

      # Eventually, true will be the default return value here
      return true if feature_flag_enabled?(@business, FeatureFlags::READ_PUBLIC_REPO_ALERTS)

      false
    end

    # Indicates whether Token Scanning is enabled for the current business
    def enabled?
      self.feature_available?
    end

    sig { returns(T::Boolean) }
    def can_enable_for_new_repos?
      true
    end

    def enable_secret_scanning_for_new_repos(actor:)
      @business.config.enable(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    # Disable secret scanning for all new private repos in an enterprise.
    def disable_secret_scanning_for_new_repos(actor:)
      @business.config.delete(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    # Indicates if secret scanning was enabled for all new private repos from the enterprise level Security & analysis page.
    def secret_scanning_enabled_for_new_repos?
      return false unless self.feature_available?

      @business.config.enabled?(SECRET_SCANNING_NEW_REPOS_KEY)
    end

    # Returns the admins to notify about secret scanning alerts for the enterprise.
    def get_admins_to_notify
      @business.admins.to_a
    end
  end
end
